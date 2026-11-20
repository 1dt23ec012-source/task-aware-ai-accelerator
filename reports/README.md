# Implementation & Physical Sign-Off Reports

This directory archives the official post-route implementation logs, static timing analysis (STA) summaries, power analyses, and physical verification sign-off reports for both the **AMD-Xilinx Artix-7 FPGA prototype** and the **SkyWater SKY130A ASIC hardening flow**.

---

## 📑 Report File Index

| Report File | Tool / Flow | Target Platform | Description |
| :--- | :--- | :--- | :--- |
| **`vivado_utilization.rpt`** | Vivado 2025.2 | Artix-7 (XC7A35T) | Post-route slice, LUT, FF, BRAM, and DSP utilization breakdown. |
| **`vivado_timing.rpt`** | Vivado STA | Artix-7 (XC7A35T) | Full post-implementation timing summary at 50.00 MHz (WNS/WHS/WPWS). |
| **`vivado_power.rpt`** | Vivado Report Power | Artix-7 (XC7A35T) | Vectorless dynamic and static on-chip power dissipation profile. |
| **`magic_drc.log`** | Magic VLSI v8.3 | SkyWater SKY130A | Hierarchical 2D mask DRC sign-off log (**0 Errors Found**). |
| **`netgen_lvs.log`** | Netgen v1.5 | SkyWater SKY130A | Subcircuit graph isomorphism verification log (**Circuits Match Uniquely**). |
| **`antenna_check.log`** | OpenROAD / TritonRoute | SkyWater SKY130A | Antenna ratio verification and diode insertion repair summary. |
| **`klayout_xor.log`** | KLayout | SkyWater SKY130A | Geometric XOR difference comparison between routed DEF and GDSII. |

---

## 1. FPGA Post-Route Sign-Off Summary (Artix-7 XC7A35T)

*Generated using AMD-Xilinx Vivado Design Suite 2025.2 (Design: `fpga_top`)*

### A. Resource Utilization
* **Slice LUTs:** `825` of `20,800` (**3.97%**)
* **Slice Registers (FF):** `831` of `41,600` (**2.00%**)
* **Occupied Slices:** `388` of `8,150` (**4.76%**)
* **Block RAM (RAMB36E1):** `8` of `50` (**16.00%**)
* **DSP48E1 Slices:** `6` of `90` (**6.67%**)
* **Global Clock Buffers (BUFG):** `1` of `32` (**3.13%**)

### B. Static Timing Analysis (50.00 MHz, Period = 20.00 ns)
* **Worst Negative Slack (WNS, Setup):** **+2.475 ns** *(MET — 0 failing endpoints out of 7,513)*
* **Total Negative Slack (TNS):** `0.000 ns`
* **Worst Hold Slack (WHS):** **+0.080 ns** *(MET — 0 failing endpoints)*
* **Total Hold Slack (THS):** `0.000 ns`
* **Worst Pulse Width Slack (WPWS):** **+9.500 ns** *(MET)*
* **Derived Maximum Clock Frequency ($F_{\max}$):** **57.06 MHz** ($T_{\min} = 20.00\text{ ns} - 2.475\text{ ns} = 17.525\text{ ns}$)

### C. On-Chip Power Dissipation Profile
* **Total On-Chip Power:** **0.089 W (89 mW)**
* **Dynamic Compute Power:** **0.017 W (17 mW / 19.1%)**
* **Device Static Leakage:** **0.072 W (72 mW / 80.9%)**
* **Junction Temperature:** `25.4°C` (Thermal margin of `59.6°C` against 85.0°C maximum limit)
* **Energy per Inference Decision:** **0.107 µJ** ($17\text{ mW} \times 4.19\ \mu\text{s}$)

---

## 2. ASIC Hardening Sign-Off Summary (SKY130A)

*Hardened from SystemVerilog RTL to GDSII using LibreLane 3.0 / OpenROAD at 50 MHz target clock.*

### A. Physical Mask Geometry
* **Silicon Die Footprint:** `1.52 mm × 1.54 mm`
* **Metal Routing Layers:** 5 Layers (`met1` through `met5`)
* **Standard-Cell Count:** `61,842` instances (including clock tree buffers and timing repair cells)
* **Sequential Cells:** `3,142` Flip-Flops
* **Routing Runtime:** `1 hour 31 minutes` (Closed with 512-pin maximum fanout after buffer right-sizing)
* **Estimated Dynamic Power:** `48.72 mW` at 50 MHz

### B. Physical Verification Closure Status

```text
========================================================================
CHECK                       TOOL                STATUS      VIOLATIONS
========================================================================
Design Rule Check (DRC)     Magic VLSI v8.3     PASSED      0 Errors
Layout Versus Schematic     Netgen v1.5         PASSED      Unique Match
Antenna Ratio Check         OpenROAD Antenna    PASSED      0 Nets
Geometry Equivalence (XOR)  KLayout             PASSED      0 Discrepancies
========================================================================
