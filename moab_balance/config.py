"""All tunable constants for the Moab ball-balancer.

Edit this file (or override fields by constructing your own ``Config``) to
re-tune for a different ball, lighting, or per-unit servo offsets.
"""

from dataclasses import dataclass, field
from typing import Tuple


@dataclass
class Config:
    # ---- Camera ----
    camera_device: int = 0
    fps: int = 30
    frame_size: int = 256
    brightness: int = 60
    contrast: int = 100
    auto_exposure: bool = True
    exposure: int = 50

    # ---- Plate geometry (do not change unless you have a custom plate) ----
    plate_diameter_m: float = 0.225
    field_of_view: float = 1.05  # plate fills ~105% of the cropped frame
    camera_rotation_deg: float = -30.0  # camera mounted at +30° vs. plate axes

    # ---- Ball detection (HSV) ----
    # Defaults are tuned for the orange ping-pong ball that ships with Moab.
    # H is OpenCV-style 0..179, S and V are 0..255.
    # If hsv_low[0] > hsv_high[0] the hue range wraps around 0 (useful for red).
    hsv_low: Tuple[int, int, int] = (5, 120, 100)
    hsv_high: Tuple[int, int, int] = (20, 255, 255)
    # Reject blobs whose enclosing-circle radius (as a fraction of frame_size)
    # falls outside this band. The Moab ping-pong ball is ~0.10–0.14 of frame.
    ball_radius_min_norm: float = 0.06
    ball_radius_max_norm: float = 0.22
    morph_kernel_px: int = 5

    # ---- PID ----
    kp: float = 75.0
    ki: float = 0.5
    kd: float = 45.0
    max_angle_deg: float = 16.0
    derivative_cutoff_hz: float = 15.0  # high-pass filter cutoff for derivative
    integral_clip: float = 0.5  # caps |sum_x|, |sum_y| in metre-seconds

    # ---- Hardware ----
    # Per-unit servo trim, in degrees. Add the value printed inside the lid of
    # your Moab here (or run the stock calibration once and copy the values).
    servo_offsets: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    servo_min_deg: float = 90.0
    servo_max_deg: float = 160.0
    plate_rest_servo_deg: float = 155.0  # plate "down" position on shutdown

    # ---- Loop ----
    log_every_n_frames: int = 60  # 0 = silent, otherwise prints every N frames


DEFAULT = Config()
