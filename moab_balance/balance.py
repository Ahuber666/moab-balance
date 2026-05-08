"""Top-level balance loop.

Owns the camera, the HAT and the controller. Runs at a fixed frequency,
captures one frame per tick, finds the ball, runs PID, converts to servo
angles, and pushes them to the HAT. Cleans up gracefully on SIGINT/SIGTERM
by lowering the plate and cutting servo power.
"""

from __future__ import annotations

import logging
import signal
import sys
import time
from typing import Optional

from .camera import Camera
from .config import Config, DEFAULT
from .controller import PID
from .hat import Hat
from .kinematics import plate_angles_to_servo_positions
from .vision import BallDetector


log = logging.getLogger("moab_balance")


class _Stopper:
    """Catch SIGINT / SIGTERM and ask the loop to exit on its next tick."""

    def __init__(self) -> None:
        self.stop = False
        signal.signal(signal.SIGINT, self._handle)
        signal.signal(signal.SIGTERM, self._handle)

    def _handle(self, signum, frame):  # noqa: ARG002
        log.info("received signal %s, shutting down", signum)
        self.stop = True


def run(cfg: Optional[Config] = None) -> int:
    cfg = cfg or DEFAULT
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(name)s %(levelname)s %(message)s",
    )
    log.info("starting moab-balance at %d Hz", cfg.fps)

    detector = BallDetector(cfg)
    pid = PID(cfg)
    stopper = _Stopper()

    period = 1.0 / cfg.fps
    o1, o2, o3 = cfg.servo_offsets
    rest = cfg.plate_rest_servo_deg

    with Hat() as hat, Camera(cfg) as cam:
        hat.enable_servos()
        # Start with the plate level so the first frame sees a sane scene.
        hat.set_servos(*_servos_for(0.0, 0.0, cfg))
        time.sleep(0.2)

        last_seen_tick = 0
        tick = 0
        next_deadline = time.monotonic()

        try:
            while not stopper.stop:
                tick += 1
                frame, _dt = cam.read()
                detected, x_m, y_m = detector(frame)

                if detected:
                    last_seen_tick = tick
                    pitch, roll = pid(x_m, y_m)
                else:
                    # Lost the ball. Don't accumulate integrator garbage,
                    # and bring the plate back to level so the ball can
                    # settle/re-acquire.
                    pid.reset()
                    pitch, roll = 0.0, 0.0

                s1, s2, s3 = _servos_for(pitch, roll, cfg)
                hat.set_servos(s1 + o1, s2 + o2, s3 + o3)

                if cfg.log_every_n_frames and tick % cfg.log_every_n_frames == 0:
                    log.info(
                        "tick=%d detected=%s pos=(% .3f,% .3f) m  "
                        "tilt=(% .2f,% .2f)° last_seen=%d",
                        tick, detected, x_m, y_m, pitch, roll, last_seen_tick,
                    )

                # Fixed-rate scheduling — sleep only the leftover time.
                next_deadline += period
                slack = next_deadline - time.monotonic()
                if slack > 0:
                    time.sleep(slack)
                else:
                    # We fell behind; resync to "now" so we don't burn CPU
                    # trying to catch up indefinitely.
                    next_deadline = time.monotonic()
        finally:
            log.info("lowering plate and disabling servos")
            try:
                hat.set_servos(rest + o1, rest + o2, rest + o3)
                time.sleep(0.2)
            finally:
                hat.disable_servos()

    return 0


def _servos_for(pitch: float, roll: float, cfg: Config):
    return plate_angles_to_servo_positions(
        pitch, roll,
        angle_min=cfg.servo_min_deg,
        angle_max=cfg.servo_max_deg,
    )


if __name__ == "__main__":  # pragma: no cover
    sys.exit(run())
