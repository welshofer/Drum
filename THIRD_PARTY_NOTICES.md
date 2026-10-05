# Third-party notices

The root MIT license covers Drum's original code and documentation. It does not
replace the licenses or copyright notices of the components listed here.

## SwiftTerm

Drum uses [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), version 1.20.0,
pinned at `5d14406844143538cd8f8851d2d8a67c1fe443e5` in `Package.resolved`.
The complete upstream [license](https://github.com/migueldeicaza/SwiftTerm/blob/5d14406844143538cd8f8851d2d8a67c1fe443e5/LICENSE)
is reproduced below without changes:

```text
Copyright (c) 2019-2026 Miguel de Icaza (https://github.com/migueldeicaza)
Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

## Bundled fonts

- **Glass TTY VT220** — Viacheslav Slavinsky (svofski), The Unlicense.
  [Source](https://github.com/svofski/glasstty) ·
  [Complete license](Drum/Resources/Fonts/Glass_TTY_VT220-LICENSE.txt).
- **Px437 IBM VGA 8×16** — The Ultimate Oldschool PC Font Pack v2.2,
  © VileR, [int10h.org](https://int10h.org/oldschool-pc-fonts/),
  [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
  Redistributed unmodified.
  [Complete license](Drum/Resources/Fonts/Px437_IBM_VGA_8x16-LICENSE.txt).

The font licenses are retained next to the fonts in the application bundle.
See [CREDITS.md](CREDITS.md) for the full attribution and source details.

`Package.resolved` also lists Apple's `swift-argument-parser` as an upstream
package dependency. It is used by SwiftTerm's separate Termcast executable,
not linked by Drum's application target. Its
[Apache 2.0 license](https://github.com/apple/swift-argument-parser/blob/6a52f3251125d74daf04fcbd5e6f08a75d074382/LICENSE.txt)
remains with the package checkout.
