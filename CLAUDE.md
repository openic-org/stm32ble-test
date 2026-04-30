# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

Maximize BLE data throughput between two STM32WB09-based targets:
- **Server**: NUCLEO-WB09KE development board (GAP peripheral / GATT server)
- **Client**: Custom STM32WB09TE board (GAP central / GATT client)

The project is based on the ST reference example:
```
/home/manuel/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1/Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Server
```
The companion client example (for reference) is at:
```
/home/manuel/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1/Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Client
```

## Hardware & Toolchain

- **MCU**: STM32WB09KE / STM32WB09TE — ARM Cortex-M0+, 32 MHz (via RC64MPLL÷2), 512 KB Flash, 64 KB RAM
- **Toolchain**: STM32CubeIDE (managed build, `arm-none-eabi-gcc`)
  - Compiler flags: `-mcpu=cortex-m0plus -mthumb -mfloat-abi=soft -DSTM32WB09`
  - Optimization: `-O2` (release) / `-Og` (debug)
- **Linker script**: `STM32CubeIDE/STM32WB09KEVX_FLASH.ld`
- **Startup**: `STM32CubeIDE/Application/User/Startup/startup_stm32wb09kevx.s`
- **Flash tool**: STM32CubeProgrammer via ST-Link USB-C connector
- **Serial terminal**: ST-Link COM port at **115200 baud** (no hardware flow control)

## Build & Flash

Open the project in **STM32CubeIDE**, then:
- **Build**: `Project → Build Project` (or Ctrl+B)
- **Flash & Debug**: `Run → Debug` (F11) — programs via ST-Link and starts a debug session
- **Flash only**: `Run → Run` (Ctrl+F11)
- **Command-line build** (from `STM32CubeIDE/` directory):
  ```bash
  make -j$(nproc) all    # release
  make -j$(nproc) DEBUG=1 all  # debug
  ```
- **Flash via CLI**:
  ```bash
  STM32_Programmer_CLI -c port=SWD freq=4000 -w output.elf -v -rst
  ```

## Memory Layout

```
FLASH (0x10040000–0x100BFFFF, 512 KB):
  Application code   : 0x10040000 – 0x100BBFFF  (496 KB)
  NVM (bonding data) : 0x100BC000 – 0x100BFFFF  (4 KB)

RAM (0x20000000–0x2000FFFF, 64 KB):
  Preamble / BLE RAM : 0x20000000 – 0x200000C0
  BLE dynamic alloc  : immediately after preamble
  Application BSS    : follows BLE allocation
  Stack (3 KB min)   : top of RAM, grows downward
```

## BLE Architecture

### Stack Initialization Flow

```
main()
  └─ MX_APPE_Init()           (app_entry.c)
       ├─ BLE_STACK_Init()    — core stack, uses BLE_DYN_ALLOC_SIZE bytes of RAM
       ├─ GATT profile init   — Service Changed characteristic
       ├─ GAP profile init    — peripheral role, static random address
       ├─ Security setup      — bonding + MITM + Secure Connections (optional)
       └─ DT_SERV_APP_Init()  — register GATT service, start advertising

Infinite loop: MX_APPE_Process() → UTIL_SEQ_Run()
```

### Cooperative Task Sequencer (UTIL_SEQ)

There is **no RTOS**. All tasks are cooperative via the ST utility sequencer. Key tasks:

| Task ID | Priority | Purpose |
|---|---|---|
| `CFG_TASK_BLE_STACK` | HIGH | BLE stack event processing |
| `CFG_TASK_DATA_TRANSFER_UPDATE_ID` | HIGH | Fire `SendData()` — main TX loop |
| `CFG_TASK_VTIMER` | HIGH | Virtual timer callbacks |
| `CFG_TASK_DATA_PHY_UPDATE_ID` | NORMAL | PHY switch (1M ↔ 2M) on B3 |
| `CFG_TASK_CONN_INTERV_UPDATE_ID` | NORMAL | Connection interval update on B2 |
| `CFG_TASK_BUTTON_1/2/3` | NORMAL | Button debounce handlers |

### Custom GATT Service (Data Throughput Service)

Service UUID: `0x00fe8080cc7a482a984a7f2ed5b3e58f`

| Characteristic | Properties | Max size | Purpose |
|---|---|---|---|
| `TX_CHAR` | NOTIFY | 255 B (244 B payload) | Server → Client notifications |
| `RX_CHAR` | READ, WRITE_NO_RESP | 255 B | Client → Server writes |
| `THROUGH_CHAR` | NOTIFY | 4 B | Throughput measurement (bytes/sec) |

Payload per notification: **244 bytes** (MTU 247 − 3 bytes GATT header).

### Key Throughput Knobs

All live in `Core/Inc/app_conf.h` and `STM32_BLE/App/app_ble.c`:

| Parameter | Default | Effect |
|---|---|---|
| `CFG_BLE_ATT_MTU_MAX` | 247 | Max ATT MTU; payload = MTU − 3 |
| `hci_le_set_data_length(251, 2120)` | called on connect | LL Data Length Extension (DLE) |
| PHY | 1 Mbps (B3 toggles to 2 Mbps) | 2M PHY doubles air throughput |
| Connection interval | 26.25 ms / 11.25 ms (B2 toggles) | Shorter = more TX slots |
| `CFG_BLE_CONN_EVENT_LENGTH_MAX` | `0xFFFFFFFF` | Allow full connection event usage |
| `CFG_BLE_CONTROLLER_2M_CODED_PHY_ENABLED` | 1 | Enables 2M / Coded PHY support |
| `CFG_BLE_CONTROLLER_DATA_LENGTH_EXTENSION_ENABLED` | 1 | Enables DLE |

### Data Send Loop (`dt_serv_app.c`)

`SendData()` runs at high priority and self-reschedules until `BLE_INSUFFICIENT_RESOURCES`:
1. Check connection alive + button enabled + CCCD enabled + flow OK
2. Increment packet counter, compute CRC8 (poly 0x97) over payload
3. Call `DT_SERV_NotifyValue()` → `aci_gatt_srv_notify()`
4. On `BLE_INSUFFICIENT_RESOURCES`: set flow OFF; resume on next `ACI_GATT_TX_POOL_AVAILABLE` event

Throughput measurement fires every 1000 ms via virtual timer, sends bytes/sec via `THROUGH_CHAR`.

### Button Mapping (Server Side)

| Button | Connected | Idle |
|---|---|---|
| B1 (PA0) | Start/stop TX notifications | — |
| B2 (PB5) | Toggle connection interval 26.25 ms ↔ 11.25 ms | Clear bonding DB |
| B3 (PB14) | Toggle PHY 1M ↔ 2M | — |

### NVM (Non-Volatile Memory)

Bonding/pairing data stored at top of flash (4 KB). Managed by `STM32_BLE/Target/blenvm.c`. Cleared with B2 when idle.

## Key Source Files

| File | Purpose |
|---|---|
| `Core/Src/main.c` | Clock config (RC64MPLL → 32 MHz), peripheral init |
| `Core/Src/app_entry.c` | BLE stack boot, UTIL_SEQ task registration |
| `Core/Inc/app_conf.h` | **All tuneable BLE parameters** |
| `STM32_BLE/App/app_ble.c` | HCI/GAP event handling, DLE + PHY requests on connect |
| `STM32_BLE/App/dt_serv.c` | GATT service + characteristic registration |
| `STM32_BLE/App/dt_serv_app.c` | `SendData()` loop, throughput timer, flow control |
| `STM32_BLE/Target/bleplat.c` | Platform abstraction for BLE stack |
| `System/Interfaces/usart_if.c` | UART1 at 115200 baud (debug output) |

## Firmware Reference

STM32Cube_FW_WB0_V1.4.1 is at `/home/manuel/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1/`. Key sub-paths:

- HAL drivers: `Drivers/STM32WB0x_HAL_Driver/`
- BLE stack library + headers: `Middlewares/ST/STM32_BLE/`
- CMSIS: `Drivers/CMSIS/`
- BSP (board support): `Drivers/BSP/STM32WB0x-Nucleo/`
- All BLE app examples: `Projects/NUCLEO-WB09KE/Applications/BLE/`
