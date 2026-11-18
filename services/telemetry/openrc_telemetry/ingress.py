"""ASGI application: POST /v1/batches, GET /healthz and an optional authenticated report read.

Never logs request bodies, addresses, headers or validation messages: only fixed categories.
"""
from __future__ import annotations

from hashlib import sha256
import hmac
import ipaddress
import logging
import time

from starlette.applications import Starlette
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException
from starlette.responses import JSONResponse, Response
from starlette.routing import Route

from . import report as report_mod
from .config import Config
from .contract import MAX_BODY, ContractError, body_digest, http_status, load_contracts
from .limits import RateLimiter
from .storage import AggStore, RawStore, StorageUnavailable

log = logging.getLogger("openrc_telemetry")

CODES = {400: "invalid_request", 401: "unauthorized", 404: "not_found", 405: "method_not_allowed",
         409: "conflict", 410: "suspended", 413: "too_large", 415: "unsupported_media", 422: "invalid_request",
         429: "rate_limited", 503: "unavailable"}


def error(status, headers=None):
    return JSONResponse({"code": CODES[status]}, status_code=status, headers=headers)


def client_address(request, trust_proxy):
    """Peer address; with a trusted proxy, the right-most X-Forwarded-For entry it appended."""
    if trust_proxy:
        forwarded = request.headers.get("x-forwarded-for", "")
        candidate = forwarded.rsplit(",", 1)[-1].strip()
        try:
            return str(ipaddress.ip_address(candidate))
        except ValueError:
            pass
    return request.client.host if request.client else "unknown"


def _json_content_type(value):
    parts = [part.strip() for part in (value or "").split(";")]
    if parts[0].lower() != "application/json":
        return False
    for param in parts[1:]:
        name, _, setting = param.partition("=")
        if name.strip().lower() == "charset" and setting.strip().strip('"').lower() != "utf-8":
            return False
    return True


def create_app(config=None, *, clock=time.time, monotonic=time.monotonic, limiter=None,
               raw=None, aggregates=None):
    config = config or Config.from_env()
    contracts = load_contracts(config.schema_dir)
    raw = raw or RawStore(config.raw_path, config.max_raw_bytes)
    aggregates = aggregates or AggStore(config.aggregates_path)
    limiter = limiter or RateLimiter(
        config.client_burst, config.client_refill_per_s, config.global_burst, config.global_refill_per_s,
        max_clients=config.max_clients, monotonic=monotonic)
    releases = frozenset(config.releases)
    suspended = frozenset(config.suspended_releases)
    token_digest = sha256(config.report_token.encode("utf-8")).digest() if config.report_token else None

    def store(body):
        """Validate then commit in one transaction; returns the HTTP status."""
        if config.suspend_all:
            return 410  # operator off switch: clients stop collecting for the rest of their process
        try:
            payload = contracts.validate_ingest(body, releases | suspended)
        except ContractError as exc:
            log.info("ingest status=%d category=%s", http_status(exc), str(exc))
            return http_status(exc)
        if payload["build"]["release_id"] in suspended:
            log.info("ingest status=410 category=suspended_release")
            return 410  # a valid batch from a release the operator suspended is never stored
        seqs = [event["seq"] for event in payload["events"]]
        try:
            outcome = raw.ingest(payload["batch_id"], body_digest(body), payload["session_id"], seqs, body,
                                 clock())
        except StorageUnavailable:
            log.warning("ingest status=503 category=storage_unavailable")
            return 503
        log.info("ingest outcome=%s", outcome)
        return 409 if outcome == "conflict" else 202

    async def post_batches(request):
        wait = limiter.check(client_address(request, config.trust_proxy))
        if wait:
            return error(429, {"Retry-After": str(wait)})
        if not _json_content_type(request.headers.get("content-type")):
            return error(415)
        if request.headers.get("content-encoding", "identity").strip().lower() not in ("", "identity"):
            return error(415)
        declared = request.headers.get("content-length")
        if declared is not None:
            if not declared.isascii() or not declared.isdigit():
                return error(400)
            if int(declared) > MAX_BODY:
                return error(413)
        body = bytearray()
        async for chunk in request.stream():
            body += chunk
            if len(body) > MAX_BODY:
                return error(413)
        status = await run_in_threadpool(store, bytes(body))
        if status == 202:
            return Response(status_code=202)
        return error(status)

    async def healthz(request):
        return JSONResponse({"status": "ok"})

    def render_report(week, release):
        title, body, digest = report_mod.material(contracts, aggregates, week, release)
        return {"title": title, "body": body, "digest": digest}

    async def weekly_report(request):
        if token_digest is None:
            return error(404)
        wait = limiter.check(client_address(request, config.trust_proxy))
        if wait:
            return error(429, {"Retry-After": str(wait)})
        header = request.headers.get("authorization", "")
        scheme, _, supplied = header.partition(" ")
        supplied_digest = sha256(supplied.strip().encode("utf-8")).digest()
        if scheme.lower() != "bearer" or not hmac.compare_digest(supplied_digest, token_digest):
            return error(401, {"WWW-Authenticate": "Bearer"})
        try:
            week = request.query_params.get("week", "")
            release = request.query_params.get("release", "")
            report_mod.parse_week(week)
            report_mod.check_release(release)
        except ContractError:
            return error(400)
        try:
            return JSONResponse(await run_in_threadpool(render_report, week, release))
        except StorageUnavailable:
            return error(503)
        except ContractError:
            log.warning("report category=invalid_aggregate")
            return error(503)

    def guarded(handler):
        async def wrapper(request):
            try:
                return await handler(request)
            except Exception:  # noqa: BLE001 - fixed category only; never log the exception text
                log.error("internal category=unhandled")
                return error(503)
        return wrapper

    async def http_exception(request, exc):
        status = exc.status_code if exc.status_code in (404, 405) else 404
        return error(status)

    app = Starlette(
        routes=[
            Route("/v1/batches", guarded(post_batches), methods=["POST"]),
            Route("/healthz", guarded(healthz), methods=["GET"]),
            Route("/v1/reports/weekly", guarded(weekly_report), methods=["GET"]),
        ],
        exception_handlers={HTTPException: http_exception},
    )
    app.router.redirect_slashes = False
    app.state.raw, app.state.aggregates, app.state.limiter = raw, aggregates, limiter
    return app
