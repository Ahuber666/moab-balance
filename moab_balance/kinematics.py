"""Inverse kinematics for the Moab plate.

Converts a desired (pitch, roll) plate orientation, in degrees, into the three
servo arm angles required to produce it. The geometry constants are taken
from Microsoft's `microsoft/moabian` (`sw/hardware.py`,
``plate_angles_to_servo_positions``); see NOTICE.
"""

from typing import Tuple

import numpy as np


# Physical constants of the Project Moab arm geometry.
ARM_LEN_MM = 55.0
SIDE_LEN_MM = 170.87
PIVOT_HEIGHT_MM = 80.0


def plate_angles_to_servo_positions(
    pitch_deg: float,
    roll_deg: float,
    arm_len: float = ARM_LEN_MM,
    side_len: float = SIDE_LEN_MM,
    pivot_height: float = PIVOT_HEIGHT_MM,
    angle_min: float = 90.0,
    angle_max: float = 160.0,
) -> Tuple[float, float, float]:
    """Return the three servo angles (degrees) for a desired plate orientation.

    The three servos are arranged 120° apart around the plate. Their indices
    correspond to the labels stamped on the Moab base plate (1, 2, 3).
    """
    z1 = pivot_height + np.sin(np.radians(roll_deg)) * (side_len / np.sqrt(3))
    r = pivot_height - np.sin(np.radians(roll_deg)) * (side_len / (2 * np.sqrt(3)))
    z2 = r + np.sin(np.radians(-pitch_deg)) * (side_len / 2)
    z3 = r - np.sin(np.radians(-pitch_deg)) * (side_len / 2)

    max_z = 2.0 * arm_len
    z1 = min(z1, max_z)
    z2 = min(z2, max_z)
    z3 = min(z3, max_z)

    s1 = 180.0 - np.degrees(np.arcsin(z1 / max_z))
    s2 = 180.0 - np.degrees(np.arcsin(z2 / max_z))
    s3 = 180.0 - np.degrees(np.arcsin(z3 / max_z))

    s1 = float(np.clip(s1, angle_min, angle_max))
    s2 = float(np.clip(s2, angle_min, angle_max))
    s3 = float(np.clip(s3, angle_min, angle_max))
    return s1, s2, s3
