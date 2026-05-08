"""HSV ball detector.

Locates a colored ball in a BGR frame and returns its position in metres,
relative to the centre of the plate.

* Image-space y grows downward; the rotation by ``camera_rotation_deg``
  takes us from image axes to plate axes (the camera is mounted at +30°
  from the plate's natural axes). This matches the convention used by
  microsoft/moabian, which means Microsoft's tuned PID gains transfer
  directly to this code.
"""

from __future__ import annotations

import math
from typing import Tuple

import cv2
import numpy as np

from .config import Config


class BallDetector:
    def __init__(self, cfg: Config) -> None:
        self.cfg = cfg
        self._scale = cfg.plate_diameter_m / (cfg.frame_size * cfg.field_of_view)
        self._min_radius_px = cfg.ball_radius_min_norm * cfg.frame_size
        self._max_radius_px = cfg.ball_radius_max_norm * cfg.frame_size
        k = cfg.morph_kernel_px
        self._kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
        self._cos_r = math.cos(math.radians(cfg.camera_rotation_deg))
        self._sin_r = math.sin(math.radians(cfg.camera_rotation_deg))

    def _hue_mask(self, hsv: np.ndarray) -> np.ndarray:
        lo = self.cfg.hsv_low
        hi = self.cfg.hsv_high
        if lo[0] <= hi[0]:
            return cv2.inRange(hsv, np.array(lo, np.uint8), np.array(hi, np.uint8))
        # Hue wraps around 0 — split into [lo[0]..179] U [0..hi[0]].
        lo_a = np.array((lo[0], lo[1], lo[2]), np.uint8)
        hi_a = np.array((179,   hi[1], hi[2]), np.uint8)
        lo_b = np.array((0,     lo[1], lo[2]), np.uint8)
        hi_b = np.array((hi[0], hi[1], hi[2]), np.uint8)
        return cv2.inRange(hsv, lo_a, hi_a) | cv2.inRange(hsv, lo_b, hi_b)

    def __call__(self, frame_bgr: np.ndarray) -> Tuple[bool, float, float]:
        """Detect the ball. Returns ``(detected, x_metres, y_metres)``."""
        hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)
        mask = self._hue_mask(hsv)
        mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, self._kernel)

        contours, _ = cv2.findContours(
            mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
        )
        if not contours:
            return False, 0.0, 0.0

        biggest = max(contours, key=cv2.contourArea)
        (cx, cy), radius = cv2.minEnclosingCircle(biggest)
        if not (self._min_radius_px < radius < self._max_radius_px):
            return False, 0.0, 0.0

        # Centre coordinates relative to the frame centre, in image pixels.
        x_px = cx - self.cfg.frame_size / 2.0
        y_px = cy - self.cfg.frame_size / 2.0

        # Rotate from camera axes to plate axes.
        x_rot = self._cos_r * x_px - self._sin_r * y_px
        y_rot = self._sin_r * x_px + self._cos_r * y_px

        return True, x_rot * self._scale, y_rot * self._scale
