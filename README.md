# gpu-toolkit

Scripts for NVIDIA GPU diagnostics, health monitoring, and process inspection. Works on any Linux node with `nvidia-smi`.

---

## Contents

### `gpu/`
| Script | What it does |
|---|---|
| `gpu-health.sh` | Full health snapshot — temp, ECC errors, power, clocks, Xid scan in dmesg |
| `xid-watch.sh` | Watch kernel ring buffer for Xid GPU errors live or from history |
| `gpu-process-map.sh` | Map GPU index → PID → username → command (who's using which GPU) |

---

## Quick usage

```bash
git clone https://github.com/pk-unix/gpu-toolkit.git
cd gpu-toolkit
chmod +x gpu/*.sh

# Full GPU health check (exits 1 if issues found)
./gpu/gpu-health.sh

# Watch for Xid errors live
./gpu/xid-watch.sh

# Show Xid history from past 1 hour
./gpu/xid-watch.sh --history 1h

# Who is using which GPU right now?
./gpu/gpu-process-map.sh

# JSON output (scriptable)
./gpu/gpu-process-map.sh --json
```

## Requirements

- `nvidia-smi` (NVIDIA driver installed)
- Root or `sudo` not required for read operations
- `dmesg` access for Xid scanning (may need root on some distros)

## Related

- **[hpc-toolkit](https://github.com/pk-unix/hpc-toolkit)** — CPU/NUMA tuning, InfiniBand, huge pages for HPC nodes
- **[slurm-node-watcher](https://github.com/pk-unix/slurm-node-watcher)** — auto-drain SLURM nodes on GPU faults
