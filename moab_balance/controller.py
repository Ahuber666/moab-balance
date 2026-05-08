"""Two-axis PID controller for the Moab plate.

The derivative term is computed from a high-pass-filtered error signal rather
than a raw finite difference: this removes the spike a naive Δerror/Δt would
produce on every new ball detection and gives a smoother, more stable
response. The cutoff frequency is configurable in ``Config``.

The controller maps:

    desired plate angle = Kp * error + Ki * Σerror·dt + Kd * d(error)/dt

where ``error`` is the ball's signed offset from the plate centre, in metres.
The sign convention matches microsoft/moabian, so the stock gains
(Kp=75, Ki=0.5, Kd=45) work out of the box.
"""

from __future__ import annotations

import math
from typing import Tuple

from .config import Config


def _clip(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else hi if v > hi else v


class _Axis:
    """Single-axis PID with high-pass-filtered derivative."""

    def __init__(self, cfg: Config) -> None:
        self.kp = cfg.kp
        self.ki = cfg.ki
        self.kd = cfg.kd
        self.max_angle = cfg.max_angle_deg
        self.integral_clip = cfg.integral_clip
        rc = 1.0 / (2.0 * math.pi * cfg.derivative_cutoff_hz)
        self._dt = 1.0 / cfg.fps
        self._alpha = rc / (rc + self._dt)
        self._prev = 0.0
        self._deriv = 0.0
        self._sum = 0.0

    def reset(self) -> None:
        self._prev = 0.0
        self._deriv = 0.0
        self._sum = 0.0

    def step(self, x: float) -> float:
        # High-pass filter on x: y[k] = α * (y[k-1] + x[k] - x[k-1])
        self._deriv = self._alpha * (self._deriv + x - self._prev)
        self._prev = x
        self._sum = _clip(
            self._sum + x * self._dt, -self.integral_clip, self.integral_clip
        )
        action = self.kp * x + self.ki * self._sum + self.kd * self._deriv
        return _clip(action, -self.max_angle, self.max_angle)


class PID:
    def __init__(self, cfg: Config) -> None:
        self._x = _Axis(cfg)
        self._y = _Axis(cfg)

    def reset(self) -> None:
        self._x.reset()
        self._y.reset()

    def __call__(self, x_m: float, y_m: float) -> Tuple[float, float]:
        """Return ``(pitch_deg, roll_deg)`` for the given ball offset."""
        return self._x.step(x_m), self._y.step(y_m)
