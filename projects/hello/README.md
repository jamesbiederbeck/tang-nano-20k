# hello

A UART transmitter that sends `Hello from Tang Nano 20K!` once a second, plus a slow binary count on the LEDs. It uses the on-board BL616 as the USB-serial bridge, so the greeting shows up on the PC with no extra hardware.

## What it does

- A one-second timer starts a small state machine.
- The state machine reads the 27 message bytes from a ROM, one at a time, into a 10-bit shift register (`{stop 1, byte, start 0}`).
- A baud divider (27 MHz ÷ 234) clocks the register out at 115200 baud, 8N1, through a flip-flop to pin 69.
- The LEDs show `count[26:21]`, inverted: a binary count that repeats about every 5 seconds.

## Files

| File | What |
|---|---|
| `hello.v` | Top module `hello` |
| `pins.cst` | `clk` pin 4, `tx` pin 69, LEDs pins 15 to 20 |
| `apio.ini` | Board and top module for APIO |

## Build, load, listen

```
source ../../env.sh
apio build
openFPGALoader -c ft2232 _build/default/hardware.fs     # to SRAM, gone on power cycle
```

Then read the board's UART at 115200 baud: `/dev/serial/by-id/usb-SIPEED_USB_Debugger_*-if01-port0`. A snippet that does this with only the Python standard library is in [`developing.md`](../../developing.md).

## Block diagram

```mermaid
graph TD
    %% Define styles
    classDef ioStyle fill:#d9efec,stroke:#0b7a75,stroke-width:1.5px,color:#1b2a2d;
    classDef blkStyle fill:#ffffff,stroke:#1b2a2d,stroke-width:1.5px,color:#1b2a2d;
    classDef accStyle fill:#ffffff,stroke:#0b7a75,stroke-width:2px,color:#0b7a75;

    %% Subgraphs / Sections
    subgraph CLK ["Clock Source"]
        clk_pin["clk<br/>pin 4 / 27 MHz crystal"]:::ioStyle
    end

    subgraph PATH_A ["A · Counter to LEDs"]
        count["count<br/>27-bit register<br/>+1 every clk"]:::blkStyle
        not_gates["NOT x6<br/>Inverters"]:::blkStyle
        leds["leds[5:0]<br/>pins 20..15<br/>Active-low LEDs"]:::ioStyle
    end

    subgraph PATH_B ["B · UART Greeting (115200 baud 8N1)"]
        wait_ctr["wait_ctr<br/>25-bit register"]:::blkStyle
        wait_cmp["= 26,999,999<br/>(One Second Timer)"]:::blkStyle
        
        div["div<br/>16-bit register"]:::blkStyle
        div_cmp["= 233<br/>(27 MHz ÷ 234)"]:::blkStyle
        
        fsm["state<br/>3-bit FSM<br/>0:gap 1:load 2:send 3:next"]:::blkStyle
        idx["idx<br/>6-bit register (0 → 26)"]:::blkStyle
        rom["message ROM<br/>27 bytes<br/>'Hello from Tang Nano 20K!\\r\\n'"]:::blkStyle
        
        shifter["shifter<br/>10-bit shift register<br/>{stop 1, byte, start 0}"]:::blkStyle
        tx_reg["tx<br/>Flip-flop"]:::blkStyle
        
        tx_pin["tx<br/>pin 69"]:::ioStyle
    end

    subgraph OFF_CHIP ["Off-Chip (On-board Bridge & PC)"]
        bl616["BL616<br/>USB-UART Bridge"]:::blkStyle
        pc["/dev/ttyUSB1<br/>on the PC"]:::ioStyle
    end

    %% Connections - Path A
    clk_pin -->|"clk"| count
    count -->|"count[26:21]"| not_gates
    not_gates -->|"6-bit inverted"| leds

    %% Connections - Path B (Timer & Clocks)
    clk_pin -->|"clk"| wait_ctr
    wait_ctr -->|"25-bit"| wait_cmp
    wait_cmp -->|"go / clear"| fsm
    wait_cmp -.->|"clear"| wait_ctr

    clk_pin -->|"clk"| div
    div -->|"16-bit"| div_cmp
    div_cmp -->|"bit_tick"| fsm
    div_cmp -.->|"clear"| div
    div_cmp -->|"bit_tick"| shifter

    %% Connections - Path B (FSM, ROM, Shifter, TX)
    clk_pin -->|"clk"| fsm
    fsm -->|"load"| shifter
    fsm -->|"inc"| idx
    idx -->|"address (6)"| rom
    rom -->|"8-bit byte"| shifter
    
    clk_pin -->|"clk"| idx
    clk_pin -->|"clk"| tx_reg

    shifter -->|"[0]"| tx_reg
    tx_reg -->|"tx"| tx_pin

    %% Off-chip connections
    tx_pin -->|"UART TX"| bl616
    bl616 -->|"USB"| pc
```

## Status

Built and loaded on the board. The greeting was read from the serial port once a second, and the LEDs counted. No testbench.
