# STM32WB09 BLE Throughput Test

Maximizing BLE data throughput between two STM32WB09-based boards using the ST BLE stack.

**Result: ~135 KB/s unidirectional, ~65 KB/s bidirectional** at 2M PHY, 7.5 ms connection interval, DLE 251 bytes, ATT MTU 247 bytes.

---

## Hardware

| Role | Board | Notes |
|------|-------|-------|
| **Server** (GAP peripheral / GATT server) | NUCLEO-WB09KE | ST development board |
| **Client** (GAP central / GATT client) | Custom STM32WB09TE | No buttons or LEDs; auto-connects on boot |

Both use the STM32WB09 — an Arm Cortex-M0+ at 32 MHz (RC64MPLL ÷ 2), 512 KB Flash, 64 KB RAM.

---

## What it does

The server advertises a custom GATT service. The client scans, connects, discovers the service, and immediately starts sending write-without-response commands. The server can also send notifications to the client (triggered by button B1). Both sides print a bytes/second measurement every second over their ST-Link UART at 115200 baud.

The focus of this project is tuning every available parameter to push throughput as high as possible with standard BLE:

- **2M PHY** — requested by the server immediately on connect
- **Data Length Extension** — `hci_le_set_data_length(251, 2120)`, giving 244-byte ATT payloads
- **7.5 ms connection interval** — the BLE minimum
- **Bonding disabled** — removes pairing overhead and NVM writes
- **Low-power mode disabled** — CPU stays at full speed

### On-connect sequence

DLE, PHY update, and connection interval update must be issued **strictly in sequence** — the BLE Link Layer only allows one LL Control Procedure at a time. Sending PHY while DLE is in progress returns error `0x07` (Memory Capacity Exceeded):

```
connect
  → hci_le_set_data_length(251, 2120)       [DLE]
  → [wait: HCI_LE_DATA_LENGTH_CHANGE event, both sides 251/251]
  → hci_le_set_phy(2M)                      [PHY]
  → [wait: HCI_LE_PHY_UPDATE_COMPLETE event]
  → aci_l2cap_connection_parameter_update_req(7.5 ms)
```

---

## Repository layout

```
server/          NUCLEO-WB09KE firmware (GAP peripheral, sends notifications)
client/          Custom STM32WB09TE firmware (GAP central, sends writes)
common/ble/      Shared assembly files (GCC 14 patch for cpu_context_switch.s)
log/             Session logs and project plan
Makefile         Top-level wrapper: make server / make client / make all
```

---

## Building

### Prerequisites

- [`STM32Cube_FW_WB0_V1.4.0`](https://github.com/STMicroelectronics/STM32CubeWB0) — provides `Drivers/` and `Utilities/`
- [`STM32Cube_FW_WB0_V1.4.1`](https://github.com/STMicroelectronics/STM32CubeWB0) — provides `Middlewares/` and `Projects/`
- `arm-none-eabi-gcc` (tested with 14.3.1 from STM32CubeIDE 2.1.1)

By default the Makefiles expect both firmware packages under `~/STM32Cube/Repository/`. Override with:

```bash
make CUBE_DRV_ROOT=/path/to/V1.4.0 CUBE_MW_ROOT=/path/to/V1.4.1
```

### Build both targets

```bash
make all              # release (-Os)
make all DEBUG=1      # debug (-Og -g3)
```

Or individually:

```bash
make server
make client
```

Build artifacts land in `server/build/` and `client/build/`.

---

## Flashing

```bash
# Server (NUCLEO-WB09KE — appears as NUCLEO-WB09KE probe)
STM32_Programmer_CLI -c port=SWD freq=4000 \
  -w server/build/BLE_DT_Server.elf -v -rst

# Client (custom board with STLINK-V3SET — specify serial number to disambiguate)
STM32_Programmer_CLI -c port=SWD freq=4000 sn=<STLINK_SN> \
  -w client/build/BLE_DT_Client.elf -v -rst
```

---

## Running

1. Flash and power both boards.
2. The client auto-scans, connects, and starts sending writes. No interaction needed.
3. Open a serial terminal at **115200 baud** on each board's ST-Link COM port.
4. On the server, press **B1** to start sending notifications to the client.
5. Watch `DataThroughput = XXXXX bytes/s` on both terminals.

### Server button mapping

| Button | While connected | While idle |
|--------|----------------|------------|
| B1 (PA0) | Start / stop TX notifications | — |
| B2 (PB5) | Toggle connection interval 26.25 ms ↔ 11.25 ms | Clear bonding NVM |
| B3 (PB14) | Toggle PHY 1M ↔ 2M | — |

---

## Throughput results

Measured on STM32WB09, 2M PHY, 7.5 ms interval, DLE=251, MTU=247:

| Mode | Measured | Theoretical max |
|------|----------|----------------|
| Unidirectional (server → client notifications) | **~135 KB/s** | 163 KB/s |
| Bidirectional (both sides sending simultaneously) | **~65 KB/s** each | 65 KB/s |

The ~18% gap in unidirectional is consumed by per-event radio overhead (~700 µs of the 7.5 ms window for radio warmup and guard time), leaving room for 4 exchanges rather than the theoretical 5. Bidirectional is at the theoretical ceiling: two full 244-byte PDUs per exchange halves the number of exchanges per event.

---

## Key files

| File | Purpose |
|------|---------|
| `server/Core/Inc/app_conf.h` | All tuneable BLE parameters (mblocks, FIFO sizes, PHY, intervals) |
| `server/STM32_BLE/App/app_ble.c` | HCI event handling, DLE + PHY + interval on-connect pipeline |
| `server/STM32_BLE/App/dt_serv_app.c` | `SendData()` notification loop, throughput timer |
| `client/STM32_BLE/App/app_ble.c` | Auto-scan, auto-connect, GAP event handling |
| `client/STM32_BLE/App/gatt_client_app.c` | GATT discovery, auto-TX start after notification enable |

---

## Based on

ST reference examples from STM32Cube_FW_WB0_V1.4.1:
- `Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Server`
- `Projects/NUCLEO-WB09KE/Applications/BLE/BLE_DataThroughput_Client`
