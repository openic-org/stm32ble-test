# Project Plan — STM32WB09 BLE Data Throughput

**Goal**: Maximize BLE data throughput between a NUCLEO-WB09KE (server) and a custom STM32WB09TE sensor board (client).

**Data flow**: Custom board (sensor source) → BLE write-without-response → Nucleo (data sink)

---

## Phase 1 — Scaffold Project Structure

Copy reference examples verbatim, then modify.

```
stm32ble-test/
├── server/     ← Nucleo-WB09KE (GAP peripheral / GATT server, receives sensor data)
├── client/     ← Custom STM32WB09TE (GAP central / GATT client, sends sensor data)
└── Makefile    ← top-level wrapper: `make server`, `make client`, `make all`
```

**Base examples** (read-only reference, do not modify):
- Server: `~/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1/Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Server`
- Client: `~/STM32Cube/Repository/STM32Cube_FW_WB0_V1.4.1/Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Client`

---

## Phase 2 — Client Board Adaptation (Custom STM32WB09TE)

The custom board has the same silicon as the Nucleo (STM32WB09) but a different package and no buttons or LEDs.

### Pin differences vs. Nucleo-WB09KE

| Function       | Nucleo-WB09KE | Custom STM32WB09TE |
|----------------|---------------|--------------------|
| USART1 TX      | PA9           | PA1                |
| USART1 RX      | PA10          | PB0                |
| LSE (32 kHz)   | Internal RC   | PB13/PB12 (crystal)|
| HSE (32 MHz)   | Crystal       | OSCIN/OSCOUT       |
| SWD CLK        | PA14          | PA3                |
| SWD IO         | PA13          | PA2                |
| Buttons        | PA0, PB5, PB14| None               |
| LEDs           | 3× GPIO       | None               |

### Changes required

- Remap USART1 to PA1 (TX) / PB0 (RX) in HAL MSP and `.ioc`
- Configure LSE source as external crystal (PB13/PB12)
- Update SWD alternate functions for PA2/PA3
- Strip all BSP button and LED code
- Replace button-triggered scan/connect/TX with **automatic boot-time behaviour**:
  - Auto-scan on boot
  - Auto-connect to first DT_SERVER device found
  - Auto-start write-without-response immediately after service discovery

---

## Phase 3 — Throughput Optimizations (Both Targets)

Applied in order of expected impact:

| # | Optimization | Parameter / Call | Default | Target |
|---|---|---|---|---|
| 1 | 2M PHY | `hci_le_set_phy()` on connect | Manual (button) | Automatic |
| 2 | Minimum connection interval | `aci_l2cap_connection_parameter_update_req()` | 26.25 ms | 7.5 ms |
| 3 | Data Length Extension | `hci_le_set_data_length(251, 2120)` | On connect | Both sides |
| 4 | Disable low-power mode | `CFG_LPM_SUPPORTED = 0` | Enabled | Disabled |
| 5 | Disable security/bonding | `CFG_BONDING_MODE = 0` | Enabled | Disabled |
| 6 | Tune BLE stack buffers | `CFG_BLE_MBLOCKS_COUNT`, `CFG_BLE_CONN_EVENT_LENGTH_MAX` | Defaults | Maximized |

---

## Phase 4 — Makefile Build System

Extract source lists, include paths, and compiler defines from each `.cproject` XML into a per-target `Makefile`. Top-level `Makefile` wraps both.

**Targets per sub-project:**

```
make all      # build ELF + BIN + HEX
make clean    # remove build artifacts
make flash    # flash via STM32_Programmer_CLI over ST-Link SWD
make debug    # build with -Og -g3
```

**Toolchain**: `arm-none-eabi-gcc`, flags `-mcpu=cortex-m0plus -mthumb -mfloat-abi=soft`

---

## Phase 5 — Measurement & Logging

Enhance the 1-second throughput report on both sides to include:

- Bytes/second (TX and RX)
- Packet loss count and percentage
- PHY in use (1M / 2M)
- Current connection interval (ms)
- Negotiated ATT MTU (bytes)

Output format: structured single-line UART log for easy parsing/graphing.

---

## Status

| Phase | Status |
|-------|--------|
| 1 — Scaffold | **Complete** |
| 2 — Client adaptation | Pending |
| 3 — Throughput optimizations | Pending |
| 4 — Makefile build system | **Complete** |
| 5 — Measurement improvements | Pending |

## Notes

### Build system (Phase 4 — done alongside Phase 1)

- STM32Cube FW is split across two versions:
  - `V1.4.0` → `Drivers/` (HAL, CMSIS, BSP) and `Utilities/`
  - `V1.4.1` → `Middlewares/` (BLE stack) and `Projects/` (Common/BLE, app examples)
- Makefile variables: `CUBE_DRV_ROOT` (V1.4.0) and `CUBE_MW_ROOT` (V1.4.1)
- `cpu_context_switch.s` has a GCC 14 incompatibility: `CPUcontextRestore` lacked `.thumb_func` marker. Patched copy lives in `common/ble/cpu_context_switch.s`.
- RAM shows 100% used — expected; the BLE stack is configured to fill available RAM by design.
- Build: `make server DEBUG=1`, `make client DEBUG=1`, or `make all`
