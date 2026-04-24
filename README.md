
# Penicillin Node-RED Simulator (IndPenSim → InfluxDB)

This repository contains a **Node-RED flow** that replays fed‑batch penicillin fermentations from the **IndPenSim** simulation benchmark and streams them as time-series data into **InfluxDB 2.x**.  
It is part of the **STAMM** platform for soft-sensor development and real-time bioprocess monitoring.

---

## 1. IndPenSim Dataset Overview

The simulator is based on the **IndPenSim** model, a structured dynamic model for industrial-scale penicillin fermentation in a 100 m³ fed-batch bioreactor. The public dataset generated from IndPenSim contains:

- **100 batches** of penicillin fermentation  
- The first **90 batches** under normal conditions (three control strategies)  
- The last **10 batches** with faults (aeration disturbances, sensor drifts, substrate variations, coolant failures)  
- At each time point, **39 process variables** and **2199 Raman spectroscopy variables** are available; here we only use online process variables (e.g., **Fs, agitation, T, pH, DO, V, CO₂₍og₎, O₂₍og₎**) and the target variable **penicillin concentration (P)**.

Batches are grouped by control strategy:

1. **Recipe-driven control (batches 1–30)**  
2. **Operator-controlled (batches 31–60)**  
3. **APC with Raman spectroscopy (batches 61–90)**  
4. **Faults / process deviations (batches 91–100)**  

In the associated research work, the 100 batches were split **80/20 (train/test)** per control strategy, and specific batches were highlighted to analyze model behavior and interpretability:

- **Batch 2** (test set) to study three representative time points over the batch.
- **Batches 15, 60, 86, and 91** to represent, respectively, the three normal control strategies and one faulty scenario in the comparative evaluation of interpretable soft sensors.

This Node-RED simulator can replay any subset of those batches as independent CSV files, preserving the original dynamic profiles and timing.

If you use this simulator in scientific work, please cite:

> Acosta‑Pavas, J.C., Robles‑Rodriguez, C.E., Griol, D., Daboussi, F., Aceves‑Lara, C.A., Corrales, D.C. (2024).  
> *Soft sensors based on interpretable learners for industrial-scale fed-batch fermentation: Learning from simulations.*  
> Computers and Chemical Engineering, 187, 108736.

---

## 2. Features

- **CSV → Node-RED → InfluxDB** streaming every 20 seconds (configurable)
- Standardized measurement and tag schema for InfluxDB:
  - `measurement`: `device_obs`
  - Tags: `device_id`, `project_name`, `batch_id`, `source`
  - Fields: `observed_property`, `value`
- Node-RED **dashboard** to:
  - Select batch file (e.g., `batch2.csv`, `batch15.csv`, `batch91.csv`)
  - Choose `project_name` (penicillin/pichia/ecoli)
  - Choose `device_id` (R1–R4)
  - Start/stop simulation
  - Reset internal counters and timestamps
- **Metadata bootstrap** button to populate the `stamm_metadata` bucket with human-readable metadata (units, labels, precision).

---

## 3. Requirements

- Docker + Docker Compose
- Running **InfluxDB 2.x** instance (local or remote)
- Optional: existing **STAMM** stacks (`stamm_raw`, `stamm_metadata` buckets, organizations, tokens)

---

## 4. Environment Configuration

Copy `.env.example` to `.env` and adjust:

```bash
# Node-RED
NODERED_PORT=1880

# InfluxDB
INFLUX_BASE_URL=http://influxdb:8086
INFLUX_ORG=stamm
INFLUX_BUCKET_RAW=stamm_raw
INFLUX_BUCKET_META=stamm_metadata
INFLUX_TOKEN=YOUR_INFLUXDB_TOKEN_HERE

# Default tags for the simulator
DEFAULT_PROJECT_NAME=penicillin
DEFAULT_DEVICE_ID=R1
DEFAULT_BATCH_FILE=batch2.csv
STREAM_INTERVAL_SECONDS=20
```

Key notes:

- `INFLUX_BASE_URL` must point to the **write** endpoint host (inside Docker, usually the service name, e.g. `http://influxdb:8086`).
- `INFLUX_TOKEN` needs **write permission** to `INFLUX_BUCKET_RAW` and `INFLUX_BUCKET_META`.
- `STREAM_INTERVAL_SECONDS` controls how fast rows are streamed.

---

## 5. Running the Stack

From the project root:

```bash
# Build and start
docker compose up -d

# Check Node-RED logs
docker compose logs -f penicillin-nodered
```

Then open Node-RED in your browser:

```text
http://localhost:1880
```

The dashboard URL is usually:

```text
http://localhost:1880/ui
```

> ⚠️ If you are running behind another reverse proxy or using a different port, adjust `NODERED_PORT` and URLs accordingly.

---

## 6. Node-RED Dashboard

The simulator dashboard contains two main control groups:

---

### 6.1 Simulation Control

Allows users to:

- Select fermentation batch (`batch2.csv`, `batch15.csv`, `batch91.csv`, etc.)
- Select `project_name` (penicillin/pichia/ecoli)
- Select `device_id` (R1–R4)
- Activate or deactivate the streaming simulation
- Reset dataset index and timestamps

Every 20 seconds (default), one row is streamed to InfluxDB as:

```text
device_obs
  device_id=<R1>
  project_name=<penicillin>
  batch_id=<batch_15>
  source=<sensor|actuator|computed>
  observed_property=<temperature>
  value=<value>
```

Timestamps are written in **nanoseconds** with reproducible stepping so that replays are deterministic.

---

### 6.2 Metadata Bootstrap (one-time action)

Writes metadata about each observed variable, including:

- `unit`
- `display_name`
- `decimals` (recommended precision)

into the **`stamm_metadata` bucket** using the same measurement:

```text
device_obs
```

#### When to click *Load metadata*

- Immediately after first deployment  
- Any time metadata definitions change  
- **Not required again unless the mapping is updated**

#### Safeguard

A built-in flag:

```js
metadata_loaded = true
```

prevents accidental re-uploads.  
If clicked again in the same session, the node displays:

```text
metadata already loaded
```

---

## 7. Workflow Description

### 7.1 Load CSV Batches

A file node reads data from `/data/batches`.  
Each batch (e.g. `batch2.csv`, `batch15.csv`, `batch60.csv`, `batch86.csv`, `batch91.csv`) contains the time-series of one IndPenSim fermentation under a specific control strategy.

Rows are parsed into JSON using a CSV parser.

### 7.2 Dataset Initialization

The flow stores the dataset in memory and prepares:

- `row counter` (current row index)  
- `base timestamp` (ns) for reproducible time stepping  

### 7.3 Streaming Loop (every `STREAM_INTERVAL_SECONDS`)

Each iteration:

1. Extracts the next row  
2. Maps columns → standardized `observed_property` names  
3. Assigns tags (`device_id`, `project_name`, `batch_id`, `source`)  
4. Builds Line Protocol for each numeric variable  
5. Sends a POST request to the InfluxDB write API  
6. Logs HTTP status (debug) and any errors

### 7.4 End of Dataset

When rows are exhausted, the node logs:

```text
End of dataset.
```

The simulation pauses until:

- The batch is reset  
- A new batch is selected  
- The streaming switch is toggled again

---

## 8. Architecture Diagram

```text
+-----------------------------+
|        Node-RED UI          |
|  Dashboard (Batch/Tags/On)  |
+-------------+---------------+
              |
              v
+-------------+---------------+
|     Batch Loader (CSV)      |
|  Reads batches from /data   |
+-------------+---------------+
              |
              v
+-------------+---------------+
|  Row Generator (every 20s)  |
|   Builds LP, timestamps     |
+-------------+---------------+
              |
              v
+-------------+---------------+
|  HTTP Write to InfluxDB     |
|  stamm_raw bucket           |
+-------------+---------------+

+-------------+---------------+
| Metadata Bootstrap (button) |
|  One-shot write to InfluxDB |
|  stamm_metadata bucket      |
+-----------------------------+
```

---

## 9. File Structure

```text
penicillin_nodered/
├─ data/
│   ├─ flows.json       # Entire Node-RED flow (simulator + metadata)
│   ├─ stamm_logo.png   # Dashboard logo
│   └─ batches/
│       ├─ batch2.csv   # Example IndPenSim batch (test batch)
│       ├─ batch15.csv
│       ├─ batch60.csv
│       ├─ batch86.csv
│       ├─ batch91.csv
│       └─ ...
├─ Dockerfile
├─ docker-compose.yaml
├─ .env.example
└─ README.md
```

You can import `data/flows.json` directly into Node-RED using the **Import → Clipboard/File** option if you prefer to run Node-RED outside Docker.

---

## 10. Troubleshooting

| Symptom                            | Likely Cause                       | Fix |
|------------------------------------|------------------------------------|-----|
| `HTTP 401 Unauthorized`            | Invalid InfluxDB token             | Update `INFLUX_TOKEN` and restart |
| `ECONNREFUSED` on write            | Wrong `INFLUX_BASE_URL` or InfluxDB down | Use correct URL, check Docker network / service name |
| Dashboard loads but no data flows  | Simulation OFF                     | Toggle **Activate Reading** switch |
| Metadata button does nothing       | Metadata already loaded            | Reset internal flag or restart Node-RED container |
| Batches not found                  | Incorrect filenames or missing CSV | Ensure files exist in `data/batches` and match dashboard options |
| Timezone / timestamps look wrong   | Wrong base timestamp or offset     | Check timestamp logic and `STREAM_INTERVAL_SECONDS` |

---

## 11. Maintenance Commands

From the project root:

| Action           | Command                               |
|------------------|---------------------------------------|
| Start stack      | `docker compose up -d`                |
| Stop stack       | `docker compose down`                 |
| Rebuild image    | `docker compose up -d --build`        |
| View logs        | `docker compose logs -f penicillin-nodered` |
| Reset volumes    | `docker compose down -v`              |

---

## 12. Summary

The **Penicillin Node-RED Simulator** provides a reproducible and configurable environment to:

- Replay **IndPenSim** penicillin batches (including the test batches selected in the interpretable soft-sensor study)  
- Stream time-series data into **InfluxDB** with a unified schema  
- Define and document variable metadata in a dedicated `stamm_metadata` bucket  
- Integrate seamlessly with the wider **STAMM** architecture (Airflow pipelines, model registry, dashboards)

You can directly connect your soft sensors, dashboards, or analytics tools to the same InfluxDB buckets to reproduce and extend the experiments from the associated publication.

---

### 📬 Contact

For questions, contact Alexander Astudillo at jairo.astudillo-lagos@inrae.fr
