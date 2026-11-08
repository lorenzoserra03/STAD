# STAD

Open-source macOS app for measuring loudspeaker impedance and Thiele-Small parameters with the
Dayton Audio DATS V3 tester.

## Features

- Impedance magnitude and phase from 10 Hz to 20 kHz (stepped sine, lock-in detection)
- Thiele-Small parameters: Fs, Re, Zmax, Qms, Qes, Qts, Le
- Added-mass method: Mms, Cms, Vas, Bl, efficiency, sensitivity
- Open, short and 1 kΩ resistor calibration
- Signal generator with input level meters
- `.zma` export
- English and Italian interface

Requires macOS 27 or later. No drivers needed.

## Background

STAD is a native macOS app written from scratch in Swift, based on standard loudspeaker
measurement methods.

## Trademarks

STAD is an independent project, not affiliated with, sponsored or endorsed by Dayton Audio.
"Dayton Audio" and "DATS" are trademarks of Dayton Audio. They are
mentioned for compatibility purposes only.

## License

[GPL-3.0](LICENSE). Modified versions must be released under the same license, with their
source code.
