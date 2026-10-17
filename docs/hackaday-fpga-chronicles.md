# Hackaday's "The FPGA Chronicles"

This repo exists because of this series by Al Williams. The articles and their comments belong to Hackaday and their authors, so they are not copied here. Read them at the links below.

| # | Article | Published |
|---|---|---|
| 1 | [Exploring The Tang Nano 20K](https://hackaday.com/2026/09/28/the-fpga-chronicles-exploring-the-tang-nano-20k/) | 2026-09-28 |
| 2 | [Open Source It](https://hackaday.com/2026/10/05/the-fpga-chronicles-open-source-it/) | 2026-10-05 |
| 3 | [Ready To Probe](https://hackaday.com/2026/10/13/the-fpga-chronicles-ready-to-probe/) | 2026-10-13 |

## Where they shaped this repo

- **Toolchain: article 2.** We use APIO with openFPGALoader, as the article does, with the same `apio.ini` shape (`board = sipeed-tang-nano-20k`, `top-module = ...`). We did not hit its `libreadline` conflict, and we skipped the VS Code extension and the RAM/flash environments.
- **LED pins: article 1.** The article's constraint example puts its LEDs on pins 15 and 16. That matches what we confirmed on the board (LEDs on 15 to 20, active low). The same example puts the user switches on pins 87 and 88. We have not tried those.
- **`ftdi_sio` and udev: article 1.** The article works around the kernel's `ftdi_sio` driver with a udev rule that unbinds it. On our board `openFPGALoader` worked with the driver left bound, once the udev permissions rule was in place. See `developing.md`.
- **Non-blocking assignments: article 3.** Its explanation of why clocked blocks should use `<=` (blocking `=` can infer latches) is why every sequential block here uses `<=`.
- **Splitting `if` chains: [Pat's comment on article 3](https://hackaday.com/2026/10/13/the-fpga-chronicles-ready-to-probe/#comment-8351177).** Pat warns about "if clauses containing unrelated logic", where one register's update hangs off another's `if`/`else` chain. After reading it, `projects/stoplight/stoplight.v` was changed to give the prescaler, seconds counter and state register one `always` block each. The testbench passed before and after.
- **Workflow template: [Pete Restall's comment on article 1](https://hackaday.com/2026/09/28/the-fpga-chronicles-exploring-the-tang-nano-20k/#comment-8346153).** Pete links `pete-restall/fpga-sv-template`, a Make, Yosys, Icarus and nextpnr setup that runs testbenches and formal checks. We have not used it. It is the likely next step for simulation and CI here.
- **The stoplight itself.** Article 1 calls a traffic light the classic state-machine exercise, then says it is impractical as a real use of an FPGA. We built one anyway as a worked example of a state machine with a testbench.

## Not used yet

- Gowin's GAO logic analyzer (article 3). It is part of the vendor IDE, which is not installed.
- verifla, the open logic-analyzer alternative article 2 mentions.
