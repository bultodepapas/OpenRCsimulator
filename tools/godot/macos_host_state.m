// Optional developer-only host observations for one checked macOS run.
// Build with the selected Apple SDK; the Python supervisor owns this process.
#import <Foundation/Foundation.h>
#import <IOKit/ps/IOPowerSources.h>
#import <dispatch/dispatch.h>
#include <errno.h>
#include <inttypes.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

static NSString *captureID;
static int gamePID;
static uint64_t sequenceNumber, outputBytes, snapshotCount, eventCount, missedTicks;
static BOOL pressureReady, finished;
static pthread_mutex_t ingressLock = PTHREAD_MUTEX_INITIALIZER;
static BOOL ingressAccepting = YES, ingressPending[2];
static uint64_t ingressDropped;
static dispatch_queue_t queue;
static dispatch_source_t pressureSource, timerSource, inputSource;
static id thermalObserver, powerObserver;
static const uint64_t byteLimit = 4 * 1024 * 1024, trailerReserve = 4096;
static const uint64_t snapshotLimit = 4096, eventLimit = 1024;

static uint64_t monotonicUS(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_UPTIME_RAW, &ts) != 0 || ts.tv_sec < 0) _exit(71);
    return (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
}

static NSDictionary *sleepAnchor(void) {
    uint64_t before = monotonicUS();
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &ts) != 0 || ts.tv_sec < 0) _exit(71);
    uint64_t continuous = (uint64_t)ts.tv_sec * 1000000 + (uint64_t)ts.tv_nsec / 1000;
    uint64_t after = monotonicUS();
    if (after < before) _exit(71);
    return @{@"uptime_before_usec": @(before), @"continuous_usec": @(continuous),
             @"uptime_after_usec": @(after)};
}

static NSDictionary *anchor(void) {
    uint64_t before = monotonicUS();
    struct timeval wall;
    if (gettimeofday(&wall, NULL) != 0 || wall.tv_sec < 0) _exit(71);
    uint64_t after = monotonicUS();
    return @{@"monotonic_usec": @(before + (after - before) / 2),
             @"unix_usec": @((uint64_t)wall.tv_sec * 1000000 + wall.tv_usec),
             @"uncertainty_usec": @(MAX((uint64_t)20000, (after - before + 1) / 2)),
             @"raw_uptime": @{@"status": @"available", @"domain": @"darwin_mach_absolute_time",
                              @"offset_lower_usec": @0, @"offset_upper_usec": @0}};
}

// A bounded pipe is drained by the supervisor. Any short/failed write is an
// incomplete artifact. The parent never waits for this process on the app thread.
static BOOL emit(NSString *type, NSDictionary *fields, BOOL trailer) {
    NSMutableDictionary *row = [fields mutableCopy];
    row[@"type"] = type;
    row[@"capture_id"] = captureID;
    row[@"sequence"] = @(sequenceNumber++);
    row[@"monotonic_usec"] = @(monotonicUS());
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:row options:0 error:&error];
    if (!json || json.length > 8191) return NO;
    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];
    uint64_t allowed = trailer ? byteLimit : byteLimit - trailerReserve;
    if (outputBytes + line.length > allowed) return NO;
    ssize_t written = write(STDOUT_FILENO, line.bytes, line.length);
    if (written != (ssize_t)line.length) return NO;
    outputBytes += (uint64_t)written;
    return YES;
}

static NSDictionary *unavailable(NSString *status, NSString *reason) {
    return @{@"status": status, @"value": [NSNull null], @"reason": reason};
}

static NSDictionary *thermal(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    if (![info respondsToSelector:@selector(thermalState)])
        return unavailable(@"unsupported", @"selector_unavailable");
    @try {
        NSInteger state = info.thermalState;
        if (state < 0 || state > 3) return unavailable(@"unknown", @"invalid_thermal_enum");
        return @{@"status": @"available", @"value": [@[@"nominal", @"fair", @"serious", @"critical"] objectAtIndex:state],
                 @"enum": @(state), @"reason": [NSNull null]};
    } @catch (NSException *exception) {
        return unavailable(@"error", @"property_query_failed");
    }
}

static NSDictionary *lowPower(void) {
    NSProcessInfo *info = [NSProcessInfo processInfo];
    if (![info respondsToSelector:@selector(isLowPowerModeEnabled)])
        return unavailable(@"unsupported", @"selector_unavailable");
    @try {
        return @{@"status": @"available", @"value": @(info.isLowPowerModeEnabled), @"reason": [NSNull null]};
    } @catch (NSException *exception) {
        return unavailable(@"error", @"property_query_failed");
    }
}

static NSDictionary *powerSource(void) {
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return unavailable(@"error", @"power_source_snapshot_failed");
    CFStringRef source = IOPSGetProvidingPowerSourceType(info);
    NSString *name = nil;
    // These are the documented IOPSGetProvidingPowerSourceType return values.
    if (source && CFEqual(source, CFSTR("AC Power"))) name = @"ac";
    else if (source && CFEqual(source, CFSTR("Battery Power"))) name = @"battery";
    else if (source && CFEqual(source, CFSTR("UPS Power"))) name = @"ups";
    CFRelease(info);
    if (!name) return unavailable(@"unknown", @"power_source_unavailable_or_unrecognized");
    return @{@"status": @"available", @"value": name, @"reason": [NSNull null]};
}

static NSDictionary *state(BOOL withPowerSource) {
    uint64_t before = monotonicUS();
    NSDictionary *t = thermal(), *l = lowPower();
    NSDictionary *p = withPowerSource ? powerSource() : nil;
    uint64_t after = monotonicUS();
    NSMutableDictionary *result = [@{@"query_start_usec": @(before), @"query_end_usec": @(after),
                                      @"thermal": t, @"low_power": l} mutableCopy];
    if (p) result[@"power_source"] = p;
    return result;
}

static void finish(NSString *reason) {
    if (finished) return;
    finished = YES;
    pthread_mutex_lock(&ingressLock);
    ingressAccepting = NO;
    uint64_t localDrops = ingressDropped + (ingressPending[0] ? 1 : 0) + (ingressPending[1] ? 1 : 0);
    pthread_mutex_unlock(&ingressLock);
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (thermalObserver) [center removeObserver:thermalObserver];
    if (powerObserver) [center removeObserver:powerObserver];
    if (timerSource) dispatch_source_cancel(timerSource);
    if (pressureSource) dispatch_source_cancel(pressureSource);
    if (inputSource) dispatch_source_cancel(inputSource);
    BOOL complete = [reason isEqualToString:@"stop"] && pressureReady && missedTicks == 0 && localDrops == 0;
    NSDictionary *endAnchor = anchor();
    NSDictionary *endSleep = sleepAnchor();
    BOOL ok = emit(@"trailer", @{@"reason": reason, @"complete": @(complete),
                               @"pressure_ready": @(pressureReady), @"snapshots": @(snapshotCount),
                               @"events": @(eventCount), @"missed_ticks": @(missedTicks),
                               @"local_drops": @(localDrops), @"os_coalesced_or_dropped": [NSNull null],
                               @"clock_end": endAnchor, @"sleep_end": endSleep}, YES);
    _exit(ok && complete ? 0 : 1);
}

static void event(NSString *name, NSDictionary *fields) {
    if (finished) return;
    if (eventCount >= eventLimit) { finish(@"event_limit"); return; }
    NSMutableDictionary *record = [fields mutableCopy];
    record[@"source"] = name;
    eventCount++;
    if (!emit(@"event", record, NO)) finish(@"write_or_byte_limit");
}

// At most one queued block per Foundation notification type. A burst is
// counted and makes the stream incomplete instead of allocating an unbounded
// queue or silently inventing the missing transitions.
static void enqueueNotification(NSString *name, unsigned index) {
    pthread_mutex_lock(&ingressLock);
    if (!ingressAccepting) { pthread_mutex_unlock(&ingressLock); return; }
    if (ingressPending[index]) {
        ingressDropped++;
        pthread_mutex_unlock(&ingressLock);
        return;
    }
    ingressPending[index] = YES;
    dispatch_async(queue, ^{ @autoreleasepool {
        event(name, state(NO));
        pthread_mutex_lock(&ingressLock);
        ingressPending[index] = NO;
        pthread_mutex_unlock(&ingressLock);
    }});
    pthread_mutex_unlock(&ingressLock);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--clock-sample") == 0) {
            char line[256];
            int length = snprintf(line, sizeof(line),
                "{\"format\":\"openrc-raw-clock-v1\",\"clock\":\"CLOCK_UPTIME_RAW\",\"raw_uptime_usec\":%" PRIu64 "}\n",
                monotonicUS());
            if (length <= 0 || (size_t)length >= sizeof(line)) return 1;
            return write(STDOUT_FILENO, line, (size_t)length) == length ? 0 : 1;
        }
        if (argc != 4 && !(argc == 5 && strcmp(argv[4], "--test-flood") == 0)) return 64;
        BOOL testMode = argc == 5;
        captureID = [NSString stringWithUTF8String:argv[1]];
        if (!captureID || ![[NSUUID alloc] initWithUUIDString:captureID]) return 64;
        char *end = NULL;
        long pid = strtol(argv[2], &end, 10);
        if (!end || *end || pid <= 0 || pid > INT32_MAX) return 64;
        gamePID = (int)pid;
        end = NULL;
        long seconds = strtol(argv[3], &end, 10);
        if (!end || *end || seconds <= 0 || seconds > 3600) return 64;
        signal(SIGPIPE, SIG_IGN);
        queue = dispatch_queue_create("org.openrc.host-state", DISPATCH_QUEUE_SERIAL);
        uint64_t deadline = monotonicUS() + (uint64_t)seconds * 1000000;
        NSDictionary *startAnchor = anchor();
        NSDictionary *startSleep = sleepAnchor();
        if (!emit(@"header", @{@"format": @"openrc-macos-host-v2", @"game_pid": @(gamePID),
                                @"clock_source": @"clock_gettime(CLOCK_UPTIME_RAW)",
                                @"clock_start": startAnchor, @"sleep_start": startSleep,
                                @"memory_pressure_initial": @"unknown",
                                @"test_mode": testMode ? @YES : @NO,
                                @"duration_limit_seconds": @(seconds), @"snapshot_limit": @(snapshotLimit),
                                @"event_limit": @(eventLimit), @"byte_limit": @(byteLimit)}, NO)) return 1;
        dispatch_async(queue, ^{
            @autoreleasepool {
                NSDictionary *before = state(NO);
                NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
                thermalObserver = [center addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                                       object:nil queue:nil usingBlock:^(NSNotification *note) {
                    enqueueNotification(@"thermal", 0);
                }];
                powerObserver = [center addObserverForName:NSProcessInfoPowerStateDidChangeNotification
                                                     object:nil queue:nil usingBlock:^(NSNotification *note) {
                    enqueueNotification(@"low_power", 1);
                }];
                NSDictionary *after = state(NO);
                if (!emit(@"initial", @{@"before": before, @"after": after,
                                         @"thermal_observer_registered": thermalObserver ? @YES : @NO,
                                         @"low_power_observer_registered": powerObserver ? @YES : @NO}, NO)) {
                    finish(@"write_or_byte_limit"); return;
                }
                if (!thermalObserver || !powerObserver) { finish(@"observer_registration_failed"); return; }
                pressureSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_MEMORYPRESSURE, 0,
                    DISPATCH_MEMORYPRESSURE_NORMAL | DISPATCH_MEMORYPRESSURE_WARN | DISPATCH_MEMORYPRESSURE_CRITICAL, queue);
                if (!pressureSource) { finish(@"pressure_registration_failed"); return; }
                dispatch_source_set_event_handler(pressureSource, ^{ @autoreleasepool {
                    unsigned long flags = dispatch_source_get_data(pressureSource);
                    event(@"memory_pressure", @{@"flags": @(flags)});
                }});
                dispatch_source_set_registration_handler(pressureSource, ^{ @autoreleasepool {
                    pressureReady = YES;
                    if (!emit(@"ready", @{@"pressure_stream": @"registered"}, NO)) finish(@"write_or_byte_limit");
                    if (testMode) {
                        // Local-only notification flood for the native fixture;
                        // it does not alter system state or induce memory pressure.
                        dispatch_apply(1000, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
                            NSString *name = (i % 2 == 0) ? NSProcessInfoThermalStateDidChangeNotification : NSProcessInfoPowerStateDidChangeNotification;
                            [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
                        });
                        finish(@"test_flood");
                    }
                }});
                dispatch_resume(pressureSource);
                timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
                inputSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, queue);
                if (!timerSource || !inputSource) { finish(@"source_creation_failed"); return; }
                dispatch_source_set_timer(timerSource, DISPATCH_TIME_NOW, NSEC_PER_SEC, 50 * NSEC_PER_MSEC);
                dispatch_source_set_event_handler(timerSource, ^{ @autoreleasepool {
                    unsigned long ticks = dispatch_source_get_data(timerSource);
                    if (ticks > 1) missedTicks += ticks - 1;
                    if (monotonicUS() >= deadline) { finish(@"duration_limit"); return; }
                    if (snapshotCount >= snapshotLimit) { finish(@"snapshot_limit"); return; }
                    snapshotCount++;
                    if (!emit(@"snapshot", state(YES), NO)) finish(@"write_or_byte_limit");
                }});
                dispatch_source_set_event_handler(inputSource, ^{ @autoreleasepool {
                    char buffer[32];
                    ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
                    if (count < 0 && errno != EINTR && errno != EAGAIN) {
                        finish(@"input_error"); return;
                    }
                    if (count == 0) {
                        // Capture an endpoint after the supervised game exits.
                        if (snapshotCount >= snapshotLimit) { finish(@"snapshot_limit"); return; }
                        snapshotCount++;
                        if (!emit(@"snapshot", state(YES), NO)) { finish(@"write_or_byte_limit"); return; }
                        finish(@"stop");
                    }
                }});
                dispatch_resume(timerSource);
                dispatch_resume(inputSource);
            }
        });
        dispatch_main();
    }
}
