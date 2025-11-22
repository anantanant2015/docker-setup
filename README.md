# 📦 Docker Installer Script

### **A universal installer, fixer, and uninstaller for Docker Engine & Docker Desktop (Ubuntu/Linux)**

**File:** `install-docker.sh`
**License:** MIT

This script provides an **idempotent**, **safe**, and **flexible** way to:

- Install **Docker Engine**
- Install **Docker Desktop (.deb)**
- Install Docker using the official **convenience script**
- Fix broken Docker installs
- Completely **uninstall** any Docker variant
- Fully **purge** all Docker data (optional)

---

# 🚀 Features

### ✅ Auto-detect Docker

Runs checks & installs Docker Engine only if missing.

### 🔧 Fix broken installs

Cleans conflicting packages, Docker Desktop leftovers, keyrings, repos.

### 💻 Install options

- **Default Docker Engine (recommended)**
- **Docker Desktop (.deb installer)**
- **Convenience script (`get.docker.com`)**

### 🧼 Full uninstall mode

| Mode                | Removes Packages | Removes Keys | Removes Repos | Removes Data          |
| ------------------- | ---------------- | ------------ | ------------- | --------------------- |
| `uninstall`         | ✔                | ✔            | ✔             | ✘                     |
| `uninstall --purge` | ✔                | ✔            | ✔             | ✔ (⚠ all Docker data) |

---

# 📥 Installation

### 1. Download

```bash
git clone https://github.com/<your-user>/<your-repo>.git
cd <your-repo>
```

### 2. Make executable

```bash
chmod +x install-docker.sh
```

---

# 🧰 Usage Guide

## ⭐ Default (auto-check + install)

```bash
./install-docker.sh
```

## 🔧 Fix + Reinstall Docker

```bash
./install-docker.sh fix
```

## 🖥 Install Docker Desktop (.deb)

```bash
./install-docker.sh desktop
```

## 🌀 Install using Convenience Script

```bash
./install-docker.sh script
```

---

# 🧹 Uninstall Modes

## 1. Basic uninstall

```bash
./install-docker.sh uninstall
```

## 2. Full uninstall + purge all Docker data

⚠ Removes images, containers, volumes, build cache, etc.

```bash
./install-docker.sh uninstall --purge
```

---

# 📦 What Gets Removed

### Packages

docker, docker.io, docker-desktop, docker-ce, containerd, buildx, compose plugin, runc, podman-docker, buildah

### Configs & keyrings

Docker repo files & keyrings

### Data directories (`--purge`)

`/var/lib/docker`, `/var/lib/containerd`

---

# 🧪 CI / Tests

Includes ShellCheck, syntax validation, uninstall simulation.

Workflow: `.github/workflows/test.yml`

---
