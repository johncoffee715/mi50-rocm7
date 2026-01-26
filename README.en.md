# Complete Guide: Installing ROCm 7.0.2 on AMD MI50 for LocalLLaMA

> 🇺🇸 English Version | 🇧🇷 [Portuguese Version](README.md)

This repository contains all necessary files and a complete step-by-step guide to install ROCm 7.0.2 on an AMD MI50 16GB/32GB GPU, even though AMD has removed official support for this GPU in recent versions.

## 📋 About the MI50

The **AMD Instinct MI50** is a datacenter GPU based on the GCN5.1 architecture (gfx906). Although AMD officially removed support after ROCm version 6.3.3, it still works perfectly on versions 6.4 and 7.0+ with a small manual adjustment to the tensor files.

### Technical Specifications
- **Architecture**: GCN5.1 (gfx906)
- **VRAM**: 16GB or 32GB
- **PCIe**: Gen3 or Gen4
- **Performance**: ~5-6x slower than a 7900XTX, but consumes ~1/10 the power

## ✅ Prerequisites

Before starting, verify that your system meets the following requirements:

### Hardware
- **CPU with PCIe Atomics**: 
  - AMD Zen 1st generation or higher
  - Intel Haswell or higher
- **Motherboard**: Any board with PCIe Gen3/Gen4 support

### BIOS Settings (Critical!)

For consumer hardware (x570/x670, etc.), configure the BIOS with the following options:

| Setting | Value |
|---------|-------|
| **Above 4G Decoding** | ✅ **Enabled** |
| **Re-Size BAR Support** | ✅ **Enabled** |
| **PCIe Slot** | Gen3 or Gen4 |
| **CSM (Compatibility Support Module)** | ❌ **Disabled** |
| **UEFI Boot Mode** | ✅ **Enabled** |
| **SR-IOV** | ✅ **Enabled** (if available) |

> ⚠️ **IMPORTANT**: Without these settings, the GPU may not be detected by the system!

### Operating System
- **Ubuntu 22.04 LTS** (Jammy) ✅
- **Ubuntu 24.04 LTS** (Noble) ✅

Other distributions may work, but are not tested in this guide.

## 📦 Repository Contents

This repository contains:

- `amdgpu-install_7.0.2.70002-1_all.deb` - Official ROCm 7.0.2 installer
- `tensor-files/` - Directory with all necessary gfx906 tensor files (extracted from rocblas 6.4)

## 🚀 Step-by-Step Installation

### Step 1: Prepare the System

```bash
# Update the system
sudo apt update
sudo apt upgrade -y

# Install prerequisites
sudo apt install -y wget python3-setuptools python3-wheel
```

### Step 2: Install ROCm 7.0.2

#### For Ubuntu 24.04 LTS (Noble):

```bash
# If you downloaded this repository, the .deb file is already included
# Otherwise, download from the official repository:
# wget https://repo.radeon.com/amdgpu-install/7.0.2/ubuntu/noble/amdgpu-install_7.0.2.70002-1_all.deb

# Install the installer
sudo apt install ./amdgpu-install_7.0.2.70002-1_all.deb

# Update repositories
sudo apt update
```

#### For Ubuntu 22.04 LTS (Jammy):

```bash
# Download from official repository (or use the file from this repository)
wget https://repo.radeon.com/amdgpu-install/7.0.2/ubuntu/jammy/amdgpu-install_7.0.2.70002-1_all.deb

# Install the installer
sudo apt install ./amdgpu-install_7.0.2.70002-1_all.deb

# Update repositories
sudo apt update
```

### Step 3: Add User to Necessary Groups

```bash
# Add your user to render and video groups
sudo usermod -a -G render,video $USER

# Apply changes (or logout/login)
newgrp render
newgrp video
```

### Step 4: Install ROCm Userspace

```bash
# Install only ROCm userspace (without DKMS, as drivers are already installed)
sudo amdgpu-install -y --usecase=rocm
```

> ⚠️ **DO NOT REBOOT YET!** You need to add the tensor files before rebooting.

### Step 5: Install gfx906 Tensor Files (CRITICAL!)

This is the most important step. AMD removed the compiled files for gfx906 from rocblas in versions 7.0+, so you need to copy the files from the `tensor-files/` directory in this repository:

```bash
# Navigate to this repository's directory
cd ~/mi50-rocm7  # or the path where you cloned/downloaded this repository

# Copy all gfx906 files to the ROCm directory
sudo cp tensor-files/*gfx906* /opt/rocm/lib/rocblas/library/

# Verify that files were copied
ls -lh /opt/rocm/lib/rocblas/library/*gfx906* | wc -l
# Should show approximately 156 files
```

> 💡 **Note**: If you prefer to use ROCm 6.4 (more stable, but slightly slower), you can install directly:
> ```bash
> sudo amdgpu-install -y --usecase=rocm --rocmrelease=6.4.0
> # In this case, tensor files are already included
> ```

### Step 6: Reboot and Verification

```bash
# Reboot the system
sudo reboot
```

> ⚠️ **Note about Secure Boot**: If you have Secure Boot enabled, you may need to add a MOK (Machine Owner Key) during boot. Follow the on-screen instructions.

After rebooting, verify that the GPU was detected:

```bash
# Verify that the GPU was detected
rocm-smi

# Should show something like:
# ========================================
# GPU Device Type   GCU   SRAM  Max Power  Max Temp
# ========================================
# gpu0   0x66a1      60    32G   250W      100C
```

If you see the GPU listed, the installation was successful! 🎉

## 🔨 Compile llama.cpp with ROCm Support

To use the MI50 with LocalLLaMA via **llama.cpp**:

```bash
# Install build dependencies
sudo apt update
sudo apt install -y build-essential cmake ninja-build pkg-config libcurl4-openssl-dev

# Clone llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
rm -rf build

# Compile with ROCm + Flash Attention
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx906 \
    -DGGML_HIP_ROCWMMA_FATTN=ON \
    -DCMAKE_BUILD_TYPE=Release

# Compile (adjust -j according to your CPU core count)
cmake --build build --config Release -- -j $(nproc)

# The executable is located at: ./build/bin/llama-cli
```

### Test Inference

```bash
# Download a GGUF model (example: Llama 2)
wget https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf

# Run inference
./build/bin/llama-cli \
    -m llama-2-7b.Q4_K_M.gguf \
    -n 256 \
    -p "Hello world" \
    -ngl 99  # GPU offload 99%
```

## 🐛 Troubleshooting

### Problem: `rocm-smi` does not detect the GPU

**Solutions:**
1. Check BIOS settings (especially "Above 4G Decoding" and "Re-Size BAR")
2. Verify that the GPU is physically connected correctly
3. Check system logs:
   ```bash
   dmesg | grep -i amdgpu
   sudo journalctl -k | grep -i amdgpu
   ```

### Problem: "gfx906" error during build

**Solution:**
- Verify that tensor files were copied correctly:
  ```bash
  ls -lh /opt/rocm/lib/rocblas/library/*gfx906* | wc -l
  # Should show approximately 156 files
  ```
- If files are missing, copy again from the `tensor-files/` directory

### Problem: Error messages in `dmesg`

**Solution:**
- Use a newer Ubuntu HWE (hardware enablement) kernel:
  ```bash
  sudo apt install linux-generic-hwe-22.04  # For Ubuntu 22.04
  sudo apt install linux-generic-hwe-24.04  # For Ubuntu 24.04
  sudo reboot
  ```

### Problem: Low performance

**Note**: The MI50 is ~5-6x slower than a 7900XTX, but uses ~1/10 the power. This is expected and normal.

### Problem: Error after kernel update

**Solution:**
- You may need to reapply tensor files after a kernel update:
  ```bash
  sudo cp tensor-files/*gfx906* /opt/rocm/lib/rocblas/library/
  sudo reboot
  ```

## 📊 Expected Performance

For reference, with ComfyUI/Flux:
- **MI50**: 7.41s/iteration (image gen), 177.68s total
- **7900XTX**: 1.44s/iteration (image gen), 32.18s total

The MI50 is slower, but is significantly cheaper and already comes with 16GB or 32GB VRAM.

## 📝 Recommended Versions

- **For Production**: ROCm 6.4 (more stable, no workarounds)
- **For Maximum Compatibility**: ROCm 7.0.2 with tensor files 6.4 (supports more new features)

Both work well with llama.cpp. Choose based on your preference for stability vs features.

## 📚 References and Useful Links

- [Official ROCm Documentation](https://rocm.docs.amd.com/)
- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp)
- [ROCm System Requirements](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html)
- [Instinct MI50 on Consumer Hardware (Reddit)](https://www.reddit.com/r/ROCm/comments/1kwirmw/instinct_mi50_on_consumer_hardware/)
- [ROCm 7.0 Install for MI50 32GB Ubuntu 24.04 LTS (Reddit - LocalLLaMA)](https://www.reddit.com/r/LocalLLaMA/comments/1o99s2u/rocm_70_install_for_mi50_32gb_ubuntu_2404_lts/)
- [ROCm 7.0 Install for MI50 32GB Ubuntu 24.04 LTS (Reddit - ROCm)](https://www.reddit.com/r/ROCm/comments/1o99swp/rocm_70_install_for_mi50_32gb_ubuntu_2404_lts/)

## ⚠️ Important Warnings

1. **Secure Boot**: If you have Secure Boot enabled, you may need to configure MOK during boot.
2. **Kernel Updates**: After kernel updates, you may need to reapply tensor files.
3. **VMs**: This guide is for bare-metal installation. For VMs (Proxmox, etc.), you may need to configure PCIe passthrough and vendor-reset.

## 🤝 Contributing

If you found issues or have improvements for this guide, feel free to open an issue or pull request!

## 📄 License

Tensor files are extracted from the rocblas 6.4.3 package from the Arch Linux User Repository (AUR) and are provided for educational purposes and legacy hardware compatibility only.

---

**Last updated**: January 2026
