"""``python -m moab_balance`` entry point."""

import sys

from .balance import run


def main() -> int:
    return run()


if __name__ == "__main__":
    sys.exit(main())
