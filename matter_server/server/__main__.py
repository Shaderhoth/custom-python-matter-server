import asyncio
import json
import logging
import os
import sys
from dataclasses import asdict, is_dataclass
from functools import partial
from pathlib import Path

import aiohttp
import aiohttp.web
from chip.exceptions import ChipStackError

from .server import CHIPControllerServer
from ..common.json_utils import CHIPJSONDecoder, CHIPJSONEncoder

logging.basicConfig(level=logging.WARN)
_LOGGER = logging.getLogger(__name__)
_LOGGER.setLevel(logging.DEBUG)

HOST = os.getenv("CHIP_WS_SERVER_HOST", "0.0.0.0")
PORT = int(os.getenv("CHIP_WS_SERVER_PORT", 8080))
STORAGE_PATH = os.getenv(
    "CHIP_WS_STORAGE", Path.joinpath(Path.home(), ".chip-storage/python-kv.json")
)


def create_success_response(message, result):
    return {
        "type": "result",
        "success": True,
        "messageId": message["messageId"],
        "result": result,
    }


def create_error_response(message, code):
    return {
        "type": "result",
        "success": False,
        "messageId": message["messageId"],
        "errorCode": code,
    }


async def websocket_handler(request, server):
    _LOGGER.info("New connection...")
    ws = aiohttp.web.WebSocketResponse()
    await ws.prepare(request)

    await ws.send_json(
        {
            "driverVersion": 0,
            "serverVersion": 0,
            "minSchemaVersion": 1,
            "maxSchemaVersion": 1,
        }
    )

    _LOGGER.info("Websocket connection ready")

    async for msg in ws:
        try:
            await handle_message(ws, server, msg)
        except Exception:
            _LOGGER.exception("Error handling message: %s", msg)

    _LOGGER.info("Websocket connection closed")
    return ws


async def handle_message(ws, server, msg):
    if msg.type != aiohttp.WSMsgType.TEXT:
        _LOGGER.debug("Ignoring %s", msg)
        return

    _LOGGER.info("Received: %s", msg.data)
    msg = json.loads(msg.data, cls=CHIPJSONDecoder)
    _LOGGER.info("Deserialized message: %s", msg)
    if msg["command"] == "start_listening":
        await ws.send_json(
            create_success_response(
                msg,
                {
                    "state": {
                        "device_controller": {
                            # Enum chip.ChipDeviceCtrl.DCState
                            "state": {
                                0: "NOT_INITIALIZED",
                                1: "IDLE",
                                2: "BLE_READY",
                                3: "RENDEZVOUS_ONGOING",
                                4: "RENDEZVOUS_CONNECTED",
                            }.get(server.device_controller.state, "UNKNOWN")
                        }
                    }
                },
            )
        )
        return

    # See if it's an instance method
    instance, _, command = msg["command"].partition(".")
    if not instance or not command:
        await ws.send_json(create_error_response(msg, "INVALID_COMMAND"))
        _LOGGER.warning("Unknown command: %s", msg["command"])
        return

    if instance == "device_controller":
        method = None
        if command[0] != "_":
            method = getattr(server.device_controller, command, None)
        if not method:
            await ws.send_json(create_error_response(msg, "INVALID_COMMAND"))
            _LOGGER.error("Unknown command: %s", msg["command"])
            return

        try:
            raw_result = method(**msg["args"])

            if asyncio.iscoroutine(raw_result):
                raw_result = await raw_result

            if is_dataclass(raw_result):
                result = asdict(raw_result)
                cls = type(raw_result)
                result["_type"] = f"{cls.__module__}.{cls.__qualname__}"

                # asdict doesn't convert dictionary keys that are dataclasses.
                # Rest already processed by `asdict`
                def convert_class_keys(val):
                    if isinstance(val, dict):
                        return {
                            k.__name__
                            if isinstance(k, type)
                            else k: convert_class_keys(v)
                            for k, v in val.items()
                        }
                    if isinstance(val, list):
                        return [convert_class_keys(v) for v in val]
                    return val

                result = convert_class_keys(result)

            else:
                result = raw_result

            from pprint import pprint

            pprint(result)

            await ws.send_json(
                create_success_response(msg, result),
                dumps=partial(json.dumps, cls=CHIPJSONEncoder),
            )
        except ChipStackError as ex:
            await ws.send_json(create_error_response(msg, str(ex)))
        except Exception:
            _LOGGER.exception("Error calling method: %s", msg["command"])
            await ws.send_json(create_error_response(msg, "UNKNOWN"))

    else:
        _LOGGER.warning("Unknown command: %s", msg["command"])
        await ws.send_json(create_error_response(msg, "INVALID_COMMAND"))


def main() -> int:
    server = CHIPControllerServer()
    server.setup(STORAGE_PATH)
    app = aiohttp.web.Application()
    app.router.add_route("GET", "/chip_ws", partial(websocket_handler, server=server))
    aiohttp.web.run_app(app, host=HOST, port=PORT)
    server.shutdown()


if __name__ == "__main__":
    sys.exit(main())