"""Pi Camera capture wrapper.

Uses OpenCV's V4L2 backend (which is what the stock Moabian image exposes
the Raspberry Pi Camera through). The native frame is 384x288; we crop a
centered 256x256 patch to match the geometry assumed by ``vision.py`` and
``kinematics.py``.
"""

from __future__ import annotations

import time
from typing import Optional, Tuple

import cv2
import numpy as np

from .config import Config


_NATIVE_W = 384
_NATIVE_H = 288


class Camera:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self.cap: Optional[cv2.VideoCapture] = None
        self._t_prev = 0.0

    def start(self) -> None:
        cap = cv2.VideoCapture(self.cfg.camera_device)
        if not cap or not cap.isOpened():
            raise RuntimeError(
                f"Could not open camera device {self.cfg.camera_device}"
            )
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, _NATIVE_W)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, _NATIVE_H)
        cap.set(cv2.CAP_PROP_FPS, self.cfg.fps)
        cap.set(cv2.CAP_PROP_MODE, 0)
        cap.set(cv2.CAP_PROP_BRIGHTNESS, self.cfg.brightness)
        cap.set(cv2.CAP_PROP_CONTRAST, self.cfg.contrast)
        # OpenCV V4L2: 0.25 = manual, 0.75 = auto (yes, inverted — that's
        # actually how V4L2 reports it).
        cap.set(
            cv2.CAP_PROP_AUTO_EXPOSURE,
            0.75 if self.cfg.auto_exposure else 0.25,
        )
        cap.set(cv2.CAP_PROP_EXPOSURE, self.cfg.exposure)
        self.cap = cap
        self._t_prev = time.monotonic()

    def stop(self) -> None:
        if self.cap is not None:
            try:
                self.cap.release()
            finally:
                self.cap = None

    def __enter__(self) -> "Camera":
        self.start()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.stop()

    def read(self) -> Tuple[np.ndarray, float]:
        """Grab a centered ``frame_size``×``frame_size`` BGR frame.

        Returns ``(frame, dt_seconds_since_last_call)``.
        """
        if self.cap is None:
            raise RuntimeError("Camera.start() has not been called")
        ok, frame = self.cap.read()
        if not ok:
            raise RuntimeError("Camera read failed")

        d = self.cfg.frame_size
        x0 = (_NATIVE_W - d) // 2
        y0 = (_NATIVE_H - d) // 2
        frame = frame[y0:y0 + d, x0:x0 + d]

        now = time.monotonic()
        dt = now - self._t_prev
        self._t_prev = now
        return frame, dt
