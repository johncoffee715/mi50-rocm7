# Guia Completo: Instalar ROCm 7.0.2 na AMD MI50 para LocalLLaMA

Este repositório contém todos os arquivos necessários e um guia passo-a-passo completo para instalar o ROCm 7.0.2 em uma GPU AMD MI50 16GB/32GB, mesmo que a AMD tenha removido o suporte oficial para esta GPU nas versões mais recentes.

## 📋 Sobre a MI50

A **AMD Instinct MI50** é uma GPU datacenter baseada na arquitetura GCN5.1 (gfx906). Embora a AMD tenha removido oficialmente o suporte após a versão ROCm 6.3.3, ela ainda funciona perfeitamente nas versões 6.4 e 7.0+ com um pequeno ajuste manual nos arquivos de tensor.

### Especificações Técnicas
- **Arquitetura**: GCN5.1 (gfx906)
- **VRAM**: 16GB ou 32GB
- **PCIe**: Gen3 ou Gen4
- **Performance**: ~5-6x mais lenta que uma 7900XTX, mas consome ~1/10 da energia

## ✅ Requisitos Prévios

Antes de começar, verifique se seu sistema atende aos seguintes requisitos:

### Hardware
- **CPU com PCIe Atomics**: 
  - AMD Zen 1ª geração ou superior
  - Intel Haswell ou superior
- **Placa-mãe**: Qualquer placa com suporte a PCIe Gen3/Gen4

### Configurações de BIOS (Crítico!)

Para hardware consumer (x570/x670, etc.), configure o BIOS com as seguintes opções:

| Configuração | Valor |
|--------------|-------|
| **Above 4G Decoding** | ✅ **Ativado** |
| **Re-Size BAR Support** | ✅ **Ativado** |
| **PCIe Slot** | Gen3 ou Gen4 |
| **CSM (Compatibility Support Module)** | ❌ **Desativado** |
| **UEFI Boot Mode** | ✅ **Ativado** |
| **SR-IOV** | ✅ **Ativado** (se disponível) |

> ⚠️ **IMPORTANTE**: Sem essas configurações, a GPU pode não ser detectada pelo sistema!

### Sistema Operacional
- **Ubuntu 22.04 LTS** (Jammy) ✅
- **Ubuntu 24.04 LTS** (Noble) ✅

Outras distribuições podem funcionar, mas não são testadas neste guia.

## 📦 Conteúdo do Repositório

Este repositório contém:

- `amdgpu-install_7.0.2.70002-1_all.deb` - Instalador oficial do ROCm 7.0.2
- `tensor-files/` - Diretório com todos os arquivos de tensor gfx906 necessários (extraídos do rocblas 6.4)

## 🚀 Instalação Passo-a-Passo

### Passo 1: Preparar o Sistema

```bash
# Atualizar o sistema
sudo apt update
sudo apt upgrade -y

# Instalar pré-requisitos
sudo apt install -y wget python3-setuptools python3-wheel
```

### Passo 2: Instalar o ROCm 7.0.2

#### Para Ubuntu 24.04 LTS (Noble):

```bash
# Se você baixou este repositório, o arquivo .deb já está incluído
# Caso contrário, baixe do repositório oficial:
# wget https://repo.radeon.com/amdgpu-install/7.0.2/ubuntu/noble/amdgpu-install_7.0.2.70002-1_all.deb

# Instalar o instalador
sudo apt install ./amdgpu-install_7.0.2.70002-1_all.deb

# Atualizar repositórios
sudo apt update
```

#### Para Ubuntu 22.04 LTS (Jammy):

```bash
# Baixar do repositório oficial (ou usar o arquivo deste repositório)
wget https://repo.radeon.com/amdgpu-install/7.0.2/ubuntu/jammy/amdgpu-install_7.0.2.70002-1_all.deb

# Instalar o instalador
sudo apt install ./amdgpu-install_7.0.2.70002-1_all.deb

# Atualizar repositórios
sudo apt update
```

### Passo 3: Adicionar Usuário aos Grupos Necessários

```bash
# Adicionar seu usuário aos grupos render e video
sudo usermod -a -G render,video $USER

# Aplicar as mudanças (ou fazer logout/login)
newgrp render
newgrp video
```

### Passo 4: Instalar ROCm Userspace

```bash
# Instalar apenas userspace ROCm (sem DKMS, já que drivers já estão instalados)
sudo amdgpu-install -y --usecase=rocm
```

> ⚠️ **NÃO REBOOTE AINDA!** Você precisa adicionar os arquivos de tensor antes do reboot.

### Passo 5: Instalar Arquivos de Tensor gfx906 (CRÍTICO!)

Este é o passo mais importante. A AMD removeu os arquivos compilados para gfx906 do rocblas nas versões 7.0+, então você precisa copiar os arquivos do diretório `tensor-files/` deste repositório:

```bash
# Navegar até o diretório deste repositório
cd ~/mi50-rocm7  # ou o caminho onde você clonou/baixou este repositório

# Copiar todos os arquivos gfx906 para o diretório do ROCm
sudo cp tensor-files/*gfx906* /opt/rocm/lib/rocblas/library/

# Verificar se os arquivos foram copiados
ls -lh /opt/rocm/lib/rocblas/library/*gfx906* | wc -l
# Deve mostrar aproximadamente 156 arquivos
```

> 💡 **Nota**: Se você preferir usar ROCm 6.4 (mais estável, mas um pouco mais lento), pode instalar diretamente:
> ```bash
> sudo amdgpu-install -y --usecase=rocm --rocmrelease=6.4.0
> # Nesse caso, os tensor files já vêm inclusos
> ```

### Passo 6: Reboot e Verificação

```bash
# Rebootar o sistema
sudo reboot
```

> ⚠️ **Nota sobre Secure Boot**: Se você tiver Secure Boot ativado, pode ser necessário adicionar uma chave MOK (Machine Owner Key) durante o boot. Siga as instruções na tela.

Após o reboot, verifique se a GPU foi detectada:

```bash
# Verificar se a GPU foi detectada
rocm-smi

# Deve mostrar algo como:
# ========================================
# GPU Device Type   GCU   SRAM  Max Power  Max Temp
# ========================================
# gpu0   0x66a1      60    32G   250W      100C
```

Se você ver a GPU listada, a instalação foi bem-sucedida! 🎉

## 🔨 Compilar llama.cpp com Suporte ROCm

Para usar a MI50 com LocalLLaMA via **llama.cpp**:

```bash
# Instalar dependências de build
sudo apt update
sudo apt install -y build-essential cmake ninja-build pkg-config libcurl4-openssl-dev

# Clonar llama.cpp
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
rm -rf build

# Compilar com ROCm + Flash Attention
HIPCXX="$(hipconfig -l)/clang" HIP_PATH="$(hipconfig -R)" \
    cmake -S . -B build \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx906 \
    -DGGML_HIP_ROCWMMA_FATTN=ON \
    -DCMAKE_BUILD_TYPE=Release

# Compilar (ajuste -j conforme número de cores da sua CPU)
cmake --build build --config Release -- -j $(nproc)

# O executável fica em: ./build/bin/llama-cli
```

### Testar Inference

```bash
# Download de um modelo GGUF (exemplo: Llama 2)
wget https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf

# Rodar inference
./build/bin/llama-cli \
    -m llama-2-7b.Q4_K_M.gguf \
    -n 256 \
    -p "Hello world" \
    -ngl 99  # GPU offload 99%
```

## 🐛 Troubleshooting

### Problema: `rocm-smi` não detecta a GPU

**Soluções:**
1. Verificar configurações de BIOS (especialmente "Above 4G Decoding" e "Re-Size BAR")
2. Verificar se a GPU está fisicamente conectada corretamente
3. Verificar logs do sistema:
   ```bash
   dmesg | grep -i amdgpu
   sudo journalctl -k | grep -i amdgpu
   ```

### Problema: Erro de "gfx906" durante o build

**Solução:**
- Verificar se copiou os arquivos de tensor corretamente:
  ```bash
  ls -lh /opt/rocm/lib/rocblas/library/*gfx906* | wc -l
  # Deve mostrar aproximadamente 156 arquivos
  ```
- Se faltarem arquivos, copie novamente do diretório `tensor-files/`

### Problema: Mensagens de erro no `dmesg`

**Solução:**
- Usar kernel Ubuntu HWE (hardware enablement) mais novo:
  ```bash
  sudo apt install linux-generic-hwe-22.04  # Para Ubuntu 22.04
  sudo apt install linux-generic-hwe-24.04  # Para Ubuntu 24.04
  sudo reboot
  ```

### Problema: Performance baixa

**Nota**: A MI50 é ~5-6x mais lenta que uma 7900XTX, mas usa ~1/10 do poder. Isso é esperado e normal.

### Problema: Erro após atualização do kernel

**Solução:**
- Pode ser necessário reaplicar os arquivos de tensor após atualização do kernel:
  ```bash
  sudo cp tensor-files/*gfx906* /opt/rocm/lib/rocblas/library/
  sudo reboot
  ```

## 📊 Performance Esperada

Para referência, com ComfyUI/Flux:
- **MI50**: 7.41s/iteração (image gen), 177.68s total
- **7900XTX**: 1.44s/iteração (image gen), 32.18s total

A MI50 é mais lenta, mas é significativamente mais barata e já vem com 16GB ou 32GB de VRAM.

## 📝 Versões Recomendadas

- **Para Produção**: ROCm 6.4 (mais estável, sem workarounds)
- **Para Máxima Compatibilidade**: ROCm 7.0.2 com tensor files 6.4 (suporta mais features novas)

Ambas funcionam bem com llama.cpp. Escolha baseado em sua preferência de estabilidade vs features.

## 📚 Referências e Links Úteis

- [Documentação Oficial ROCm](https://rocm.docs.amd.com/)
- [llama.cpp GitHub](https://github.com/ggml-org/llama.cpp)
- [ROCm System Requirements](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html)
- [Instinct MI50 em Hardware Consumer (Reddit)](https://www.reddit.com/r/ROCm/comments/1kwirmw/instinct_mi50_on_consumer_hardware/)
- [ROCm 7.0 Install para MI50 32GB Ubuntu 24.04 LTS (Reddit - LocalLLaMA)](https://www.reddit.com/r/LocalLLaMA/comments/1o99s2u/rocm_70_install_for_mi50_32gb_ubuntu_2404_lts/)
- [ROCm 7.0 Install para MI50 32GB Ubuntu 24.04 LTS (Reddit - ROCm)](https://www.reddit.com/r/ROCm/comments/1o99swp/rocm_70_install_for_mi50_32gb_ubuntu_2404_lts/)

## ⚠️ Avisos Importantes

1. **Secure Boot**: Se você tiver Secure Boot ativado, pode ser necessário configurar MOK durante o boot.
2. **Atualizações de Kernel**: Após atualizações de kernel, pode ser necessário reaplicar os arquivos de tensor.
3. **VMs**: Este guia é para instalação bare-metal. Para VMs (Proxmox, etc.), pode ser necessário configurar PCIe passthrough e vendor-reset.

## 🤝 Contribuindo

Se você encontrou problemas ou tem melhorias para este guia, sinta-se à vontade para abrir uma issue ou pull request!

## 📄 Licença

Os arquivos de tensor são extraídos do pacote rocblas 6.4.3 do Arch Linux User Repository (AUR) e são fornecidos apenas para fins educacionais e de compatibilidade com hardware legado.

---

**Última atualização**: Janeiro 2026
