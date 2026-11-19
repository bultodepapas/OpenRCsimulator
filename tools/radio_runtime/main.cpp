// SPDX-License-Identifier: MIT
// Original experimental host for a locally supplied EdgeTX simulator library.
// This host is for inspection and training observations, not flight control.

#include "simulatorinterface.h"

#include <QCommandLineParser>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLibrary>
#include <QRegularExpression>
#include <QSysInfo>
#include <QTimer>
#include <SDL.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <thread>
#include <utility>

namespace {
constexpr auto kExpectedSourceCommit = "0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99";
constexpr auto kExpectedName = "edgetx-t18h7";
constexpr int kWidth = 480;
constexpr int kHeight = 272;
constexpr int kStride = kWidth * 2;
constexpr int kFrameBytes = kStride * kHeight;
constexpr int kMaxChannelEvents = 256;
constexpr int kMaxErrors = 16;
constexpr int kMaxErrorChars = 512;
constexpr qint64 kMaxPluginBytes = qint64{1024} * 1024 * 1024;

// If firmware startup or shutdown blocks the event loop, a Qt timer cannot
// enforce a deadline. A forced process exit may leave no receipt.
class HardDeadline {
public:
  explicit HardDeadline(int timeoutMs) : worker_([this, timeoutMs] {
    std::unique_lock<std::mutex> lock(mutex_);
    if (!doneCondition_.wait_for(lock, std::chrono::milliseconds(timeoutMs),
                                 [this] { return done_; })) {
      std::fputs("Firmware host watchdog expired; no complete receipt guaranteed.\n", stderr);
      std::fflush(stderr);
      std::_Exit(124);
    }
  }) {}

  ~HardDeadline() {
    {
      std::lock_guard<std::mutex> lock(mutex_);
      done_ = true;
    }
    doneCondition_.notify_one();
    worker_.join();
  }

  HardDeadline(const HardDeadline &) = delete;
  HardDeadline &operator=(const HardDeadline &) = delete;

private:
  std::mutex mutex_;
  std::condition_variable doneCondition_;
  bool done_ = false;
  std::thread worker_;
};

struct Channel {
  bool seen = false;
  qint64 count = 0;
  qint32 minimum = 0;
  qint32 maximum = 0;
  qint32 last = 0;
  qint32 limit = 0;
  qint64 lastMs = -1;
};

struct Observations {
  QElapsedTimer elapsed;
  bool started = false;
  bool stopped = false;
  bool deadlineReached = false;
  qint64 frameCount = 0;
  qint64 firstFrameMs = -1;
  qint64 lastFrameMs = -1;
  bool lastBacklight = false;
  QByteArray latestFrame;
  qint64 heartbeatCount = 0;
  qint32 lastHeartbeatLoops = 0;
  qint64 lastHeartbeatTimestamp = 0;
  qint64 lastHeartbeatMs = -1;
  qint64 channelCount = 0;
  qint64 runtimeErrorCount = 0;
  qint64 internalErrorCount = 0;
  std::array<Channel, 32> channels{};
  QJsonArray channelEvents;
  QJsonArray sweepEvents;
  QJsonArray errors;
  QString factoryName;
  QString simulatorName;

  void error(const QString &kind, const QString &message) {
    if (kind == QStringLiteral("runtime"))
      ++runtimeErrorCount;
    else
      ++internalErrorCount;
    if (errors.size() < kMaxErrors) {
      errors.append(QJsonObject{{"kind", kind},
                                {"message", message.left(kMaxErrorChars)},
                                {"elapsed_ms", elapsed.isValid() ? elapsed.elapsed() : -1}});
    }
  }
};

bool isAscii(const QString &value) {
  for (QChar c : value) {
    if (c.unicode() > 0x7f || c.isNull())
      return false;
  }
  return true;
}

bool privateDirectory(const QString &input, QString &canonical, QString &error) {
  QFileInfo info(input);
  if (!info.isAbsolute() || !isAscii(input) || !info.exists() || !info.isDir()) {
    error = QStringLiteral("A private-copy path must be an existing absolute ASCII directory: %1").arg(input);
    return false;
  }
  canonical = info.canonicalFilePath();
  if (canonical.isEmpty() || !isAscii(canonical) || QDir(canonical).isRoot()) {
    error = QStringLiteral("Private-copy path resolved to an invalid, non-ASCII, or root directory: %1").arg(input);
    return false;
  }
  return true;
}

bool writeNewFile(const QString &path, const QByteArray &bytes, QString &error) {
  QFile file(path);
  if (!file.open(QIODevice::WriteOnly | QIODevice::NewOnly)) {
    error = QStringLiteral("Cannot create %1: %2").arg(path, file.errorString());
    return false;
  }
  if (file.write(bytes) != bytes.size() || !file.flush()) {
    error = QStringLiteral("Cannot write %1: %2").arg(path, file.errorString());
    return false;
  }
  return true;
}

class SmokeHost final : public QObject {
  Q_OBJECT
public:
  SmokeHost(QCoreApplication &app, SimulatorInterface *simulator, Observations &obs,
            QString sdPath, QString settingsPath, int durationMs, int sweepIndex)
      : app_(app), simulator_(simulator), obs_(obs), sdPath_(std::move(sdPath)),
        settingsPath_(std::move(settingsPath)), durationMs_(durationMs), sweepIndex_(sweepIndex) {}

  bool connectSignals() {
    // The pinned interface is a QObject in the dynamically loaded library.
    // String connections avoid a link-time reference to its staticMetaObject.
    bool ok = true;
    ok = bool(QObject::connect(simulator_, SIGNAL(started()), this, SLOT(onStarted()))) && ok;
    ok = bool(QObject::connect(simulator_, SIGNAL(stopped()), this, SLOT(onStopped()))) && ok;
    ok = bool(QObject::connect(simulator_, SIGNAL(lcdChange(bool)), this, SLOT(onLcdChange(bool)))) && ok;
    ok = bool(QObject::connect(simulator_, SIGNAL(channelOutValueChange(quint8,qint32,qint32)),
                               this, SLOT(onChannel(quint8,qint32,qint32)))) && ok;
    ok = bool(QObject::connect(simulator_, SIGNAL(heartbeat(qint32,qint64)),
                               this, SLOT(onHeartbeat(qint32,qint64)))) && ok;
    ok = bool(QObject::connect(simulator_, SIGNAL(runtimeError(QString)),
                               this, SLOT(onRuntimeError(QString)))) && ok;
    return ok;
  }

  void begin() {
    simulator_->setSdPath(sdPath_, settingsPath_);
    simulator_->init();
    simulator_->start(nullptr, false);
    // start() emits started() under an upstream mutex; only proceed once it returns.
    if (!obs_.started) {
      obs_.error("internal", "Simulator did not emit started");
      QTimer::singleShot(0, &app_, &QCoreApplication::quit);
      return;
    }
    if (sweepIndex_ >= 0) {
      const std::array<int, 3> values{{-1024, 0, 1024}};
      for (int i = 0; i < int(values.size()); ++i) {
        QTimer::singleShot((durationMs_ * (i + 1)) / 4, this, [this, value = values[i]] {
          if (!obs_.stopped) {
            simulator_->setInputValue(SimulatorInterface::INPUT_SRC_STICK,
                                      static_cast<uint8_t>(sweepIndex_), static_cast<int16_t>(value));
            obs_.sweepEvents.append(QJsonObject{{"elapsed_ms", obs_.elapsed.elapsed()},
                                                {"stick_index", sweepIndex_}, {"value", value}});
          }
        });
      }
    }
    QTimer::singleShot(durationMs_, this, [this] {
      obs_.deadlineReached = true;
      app_.quit();
    });
  }

private slots:
  // Never re-enter simulator methods from started/stopped: upstream emits
  // these with a non-recursive mutex held.
  void onStarted() { obs_.started = true; }
  void onStopped() { obs_.stopped = true; }

  void onLcdChange(bool backlight) {
    uint8_t *buffer = simulator_->getLcd();
    if (buffer) {
      if (obs_.latestFrame.size() != kFrameBytes)
        obs_.latestFrame.resize(kFrameBytes);
      std::memcpy(obs_.latestFrame.data(), buffer, kFrameBytes);
      ++obs_.frameCount;
      obs_.lastFrameMs = obs_.elapsed.elapsed();
      if (obs_.firstFrameMs < 0)
        obs_.firstFrameMs = obs_.lastFrameMs;
      obs_.lastBacklight = backlight;
    } else {
      obs_.error("internal", "LCD change had a null framebuffer");
    }
    // Match Companion's copy-before-acknowledgment handshake, including on
    // an unexpected null pointer so the firmware is not left waiting.
    simulator_->lcdFlushed();
  }

  void onChannel(quint8 index, qint32 value, qint32 limit) {
    ++obs_.channelCount;
    const qint64 now = obs_.elapsed.elapsed();
    if (index < obs_.channels.size()) {
      Channel &c = obs_.channels[index];
      if (!c.seen) {
        c.seen = true;
        c.minimum = c.maximum = value;
      } else {
        c.minimum = std::min(c.minimum, value);
        c.maximum = std::max(c.maximum, value);
      }
      ++c.count;
      c.last = value;
      c.limit = limit;
      c.lastMs = now;
    }
    if (obs_.channelEvents.size() < kMaxChannelEvents) {
      obs_.channelEvents.append(QJsonObject{{"elapsed_ms", now}, {"index", int(index)},
                                            {"value", value}, {"limit", limit}});
    }
  }

  void onHeartbeat(qint32 loops, qint64 timestamp) {
    ++obs_.heartbeatCount;
    obs_.lastHeartbeatLoops = loops;
    obs_.lastHeartbeatTimestamp = timestamp;
    obs_.lastHeartbeatMs = obs_.elapsed.elapsed();
  }

  void onRuntimeError(const QString &error) {
    obs_.error("runtime", error);
    QTimer::singleShot(0, &app_, &QCoreApplication::quit);
  }

private:
  QCoreApplication &app_;
  SimulatorInterface *simulator_;
  Observations &obs_;
  QString sdPath_;
  QString settingsPath_;
  int durationMs_;
  int sweepIndex_;
};

QJsonObject makeReceipt(const Observations &o, const QString &pluginPath,
                        const QString &pluginHash, const QString &expectedHash,
                        const QString &sdPath, const QString &settingsPath,
                        int durationMs, int sweepIndex, bool screenshotWritten, bool audioInitialized) {
  SDL_version sdlRuntime;
  SDL_GetVersion(&sdlRuntime);
  QJsonArray channelSummaries;
  for (int i = 0; i < int(o.channels.size()); ++i) {
    const Channel &c = o.channels[i];
    if (c.seen) {
      channelSummaries.append(QJsonObject{{"index", i}, {"count", c.count},
                                          {"min", c.minimum}, {"max", c.maximum},
                                          {"last", c.last}, {"last_limit", c.limit},
                                          {"last_elapsed_ms", c.lastMs}});
    }
  }
  const bool observationsMet = o.deadlineReached && o.started && o.stopped &&
      o.frameCount > 0 && o.heartbeatCount > 0 && o.channelCount > 0 &&
      o.runtimeErrorCount == 0 && o.internalErrorCount == 0 && screenshotWritten;
  const QString frameHash = o.latestFrame.isEmpty() ? QString() : QString::fromLatin1(
      QCryptographicHash::hash(o.latestFrame, QCryptographicHash::Sha256).toHex());
  return QJsonObject{
      {"schema", "openrc-edgetx-native-smoke-v1"},
      {"created_utc", QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs)},
      {"basic_observations_met", observationsMet},
      {"expected_edgetx_source_commit", kExpectedSourceCommit},
      {"compiled_header_hashes_match_pin", true},
      {"plugin_origin_verified_by_source_commit", false},
      {"plugin", QJsonObject{{"path", pluginPath}, {"sha256", pluginHash},
                             {"expected_sha256", expectedHash},
                             {"expected_sha256_matched", expectedHash.isEmpty() ? QJsonValue(QJsonValue::Null)
                                                                                : QJsonValue(expectedHash == pluginHash)},
                             {"factory_name", o.factoryName}, {"simulator_name", o.simulatorName}}},
      {"environment", QJsonObject{{"qt_build_version", QT_VERSION_STR}, {"qt_runtime_version", qVersion()},
                                  {"sdl_build_version", QStringLiteral("%1.%2.%3").arg(SDL_MAJOR_VERSION).arg(SDL_MINOR_VERSION).arg(SDL_PATCHLEVEL)},
                                  {"sdl_runtime_version", QStringLiteral("%1.%2.%3").arg(sdlRuntime.major).arg(sdlRuntime.minor).arg(sdlRuntime.patch)},
                                  {"os", QSysInfo::prettyProductName()}, {"architecture", QSysInfo::currentCpuArchitecture()}}},
      {"audio", QJsonObject{{"driver", "dummy"}, {"initialized", audioInitialized}, {"audible_output_qualified", false}}},
      {"private_sd_copy", sdPath}, {"private_settings_copy", settingsPath},
      {"requested_duration_ms", durationMs}, {"elapsed_ms", o.elapsed.elapsed()},
      {"startup_checks_enabled", false}, {"started_signal", o.started},
      {"stopped_signal", o.stopped}, {"deadline_reached", o.deadlineReached},
      {"lcd", QJsonObject{{"frames_received", o.frameCount}, {"first_elapsed_ms", o.firstFrameMs},
                          {"last_elapsed_ms", o.lastFrameMs}, {"last_backlight", o.lastBacklight},
                          {"width", kWidth}, {"height", kHeight}, {"stride_bytes", kStride},
                          {"format", "RGB565-native-endian"}, {"expected_bytes", kFrameBytes},
                          {"coherence_verified", false},
                          {"latest_sha256", frameHash},
                          {"file", screenshotWritten ? QStringLiteral("latest.rgb565") : QString()}}},
      {"heartbeat", QJsonObject{{"count", o.heartbeatCount}, {"last_loops", o.lastHeartbeatLoops},
                                {"last_firmware_timestamp_ms", o.lastHeartbeatTimestamp},
                                {"last_host_elapsed_ms", o.lastHeartbeatMs}}},
      {"channel_notifications", QJsonObject{{"total", o.channelCount},
                                            {"events_truncated", o.channelCount > o.channelEvents.size()},
                                            {"events", o.channelEvents}, {"summaries", channelSummaries},
                                            {"coherent_snapshot_or_freshness_proven", false}}},
      {"sweep", QJsonObject{{"enabled", sweepIndex >= 0}, {"stick_index", sweepIndex},
                            {"training_only", true}, {"sent", o.sweepEvents},
                            {"channel_mapping_verified", false}}},
      {"runtime_error_count", o.runtimeErrorCount}, {"internal_error_count", o.internalErrorCount},
      {"errors_truncated", o.runtimeErrorCount + o.internalErrorCount > o.errors.size()},
      {"errors", o.errors}, {"named_model_loaded_verified", false},
      {"telemetry_verified", false}, {"flight_admission", false}};
}
} // namespace

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  QCoreApplication::setApplicationName("openrc-edgetx-smoke");
  QCommandLineParser parser;
  parser.setApplicationDescription("Bounded experimental EdgeTX T18-H7 observation host");
  parser.addHelpOption();
  const QCommandLineOption pluginOpt("plugin", "Absolute path to a trusted simulator library", "path");
  const QCommandLineOption sdOpt("sd-copy", "Existing absolute ASCII path to a private SD copy", "path");
  const QCommandLineOption settingsOpt("settings-copy", "Existing absolute ASCII path to private settings copy", "path");
  const QCommandLineOption outputOpt("output", "New absolute output directory; must not exist", "path");
  const QCommandLineOption durationOpt("duration-ms", "Event-loop observation duration: 1500 to 30000 ms", "ms", "5000");
  const QCommandLineOption hashOpt("expected-plugin-sha256", "Expected plugin SHA-256, if independently known", "hex");
  const QCommandLineOption sweepOpt("sweep-stick", "Optional training-only physical stick index: 0 to 3", "index");
  parser.addOptions({pluginOpt, sdOpt, settingsOpt, outputOpt, durationOpt, hashOpt, sweepOpt});
  parser.process(app);

  auto fail = [](const QString &message) {
    std::fprintf(stderr, "%s\n", qPrintable(message));
    return 2;
  };
  if (!parser.isSet(pluginOpt) || !parser.isSet(sdOpt) ||
      !parser.isSet(settingsOpt) || !parser.isSet(outputOpt))
    return fail("--plugin, --sd-copy, --settings-copy and --output are required");

  bool validDuration = false;
  const int duration = parser.value(durationOpt).toInt(&validDuration);
  if (!validDuration || duration < 1500 || duration > 30000)
    return fail("--duration-ms must be an integer between 1500 and 30000");
  int sweepIndex = -1;
  if (parser.isSet(sweepOpt)) {
    bool validIndex = false;
    sweepIndex = parser.value(sweepOpt).toInt(&validIndex);
    if (!validIndex || sweepIndex < 0 || sweepIndex > 3)
      return fail("--sweep-stick must be an integer between 0 and 3");
  }
  const QString expectedHash = parser.value(hashOpt).toLower();
  if (parser.isSet(hashOpt) &&
      !QRegularExpression("^[0-9a-f]{64}$").match(expectedHash).hasMatch())
    return fail("--expected-plugin-sha256 must contain exactly 64 hexadecimal characters");

  const QFileInfo pluginInfo(parser.value(pluginOpt));
  if (!pluginInfo.isAbsolute() || !pluginInfo.isFile() || pluginInfo.size() <= 0 ||
      pluginInfo.size() > kMaxPluginBytes)
    return fail("--plugin must be an existing absolute regular file no larger than 1 GiB");
  const QString pluginPath = pluginInfo.canonicalFilePath();
  QString sdPath, settingsPath, error;
  if (!privateDirectory(parser.value(sdOpt), sdPath, error) ||
      !privateDirectory(parser.value(settingsOpt), settingsPath, error))
    return fail(error);
  const QString outputPath = QDir::cleanPath(parser.value(outputOpt));
  if (!QDir::isAbsolutePath(outputPath) || QDir(outputPath).isRoot())
    return fail("--output must be an absolute non-root path");

  QFile pluginFile(pluginPath);
  if (!pluginFile.open(QIODevice::ReadOnly))
    return fail(QStringLiteral("Cannot read plugin: %1").arg(pluginFile.errorString()));
  QCryptographicHash hasher(QCryptographicHash::Sha256);
  if (!hasher.addData(&pluginFile))
    return fail(QStringLiteral("Cannot hash plugin: %1").arg(pluginFile.errorString()));
  pluginFile.close();
  const QString pluginHash = QString::fromLatin1(hasher.result().toHex());
  if (!expectedHash.isEmpty() && expectedHash != pluginHash)
    return fail("Plugin SHA-256 did not match the expected value");

  std::error_code fsError;
#ifdef _WIN32
  const std::filesystem::path nativeOutputPath(outputPath.toStdWString());
#else
  const std::filesystem::path nativeOutputPath(QFile::encodeName(outputPath).constData());
#endif
  const bool madeDirectory = std::filesystem::create_directory(nativeOutputPath, fsError);
  if (!madeDirectory || fsError)
    return fail(QStringLiteral("Cannot exclusively create output directory: %1").arg(outputPath));

  HardDeadline watchdog(duration + 10000);
  Observations obs;
  obs.elapsed.start();
  // Companion initializes SDL before starting the firmware. Keep this
  // observation tool silent and independent of the user's audio device.
  qputenv("SDL_AUDIODRIVER", "dummy");
  SDL_SetMainReady();
  const bool audioInitialized = SDL_Init(SDL_INIT_AUDIO) == 0;
  if (!audioInitialized)
    obs.error("internal", QStringLiteral("SDL audio initialization failed: %1").arg(QString::fromUtf8(SDL_GetError())));
  QLibrary library(pluginPath);
  // Reject unresolved runtime symbols now, rather than when a later menu or
  // control operation first calls them (the no-SDL upstream build can omit one).
  library.setLoadHints(QLibrary::ResolveAllSymbolsHint);
  SimulatorInterface *simulator = nullptr;
  if (audioInitialized && !library.load()) {
    obs.error("internal", QStringLiteral("Library load failed: %1").arg(library.errorString()));
  } else if (audioInitialized) {
    using RegisterSimulator = SimulatorFactory *(*)();
    auto registerSimulator = reinterpret_cast<RegisterSimulator>(library.resolve("registerSimu"));
    if (!registerSimulator) {
      obs.error("internal", QStringLiteral("registerSimu not found: %1").arg(library.errorString()));
    } else {
      SimulatorFactory *factory = registerSimulator();
      if (!factory) {
        obs.error("internal", "registerSimu returned no factory");
      } else {
        obs.factoryName = factory->name();
        if (obs.factoryName != QString::fromLatin1(kExpectedName)) {
          obs.error("internal", "Unexpected simulator factory name");
        } else {
          simulator = factory->create();
          if (!simulator)
            obs.error("internal", "Factory returned no simulator");
        }
        delete factory;
      }
    }
  }

  if (simulator) {
    obs.simulatorName = simulator->name();
    if (obs.simulatorName != QString::fromLatin1(kExpectedName)) {
      obs.error("internal", "Unexpected simulator instance name");
    } else {
      SmokeHost host(app, simulator, obs, sdPath, settingsPath, duration, sweepIndex);
      if (!host.connectSignals()) {
        obs.error("internal", "One or more simulator signals could not be connected");
      } else {
        host.begin();
        app.exec();
      }
      // Both calls are made on the owner thread, after started() has returned.
      if (simulator->isRunning())
        simulator->stop();
    }
    delete simulator;
    simulator = nullptr;
  }
  if (library.isLoaded() && !library.unload())
    obs.error("internal", QStringLiteral("Library unload failed: %1").arg(library.errorString()));
  SDL_Quit();

  bool screenshotWritten = false;
  if (!obs.latestFrame.isEmpty()) {
    screenshotWritten = writeNewFile(outputPath + "/latest.rgb565", obs.latestFrame, error);
    if (!screenshotWritten)
      obs.error("internal", error);
  }
  const QJsonObject receipt = makeReceipt(obs, pluginPath, pluginHash, expectedHash,
                                          sdPath, settingsPath, duration, sweepIndex, screenshotWritten, audioInitialized);
  if (!writeNewFile(outputPath + "/receipt.json", QJsonDocument(receipt).toJson(QJsonDocument::Indented), error))
    return fail(error);
  std::fprintf(stderr, "Receipt: %s\n", qPrintable(outputPath + "/receipt.json"));
  return receipt.value("basic_observations_met").toBool() ? 0 : 1;
}

#include "main.moc"
