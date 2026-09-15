# stim/

Contrato numérico dos perfis de volta do protótipo ERS EP4CE6.

Leia **[SCALE.md](SCALE.md)** antes de gerar, commitar ou apontar a ROM.

Arquivos desta volta (**EXEMPLO**, não é circuito real):

| Arquivo | Uso |
|---------|-----|
| `volta_sintetica.mif` | Quartus Memory Initialization File (cópia idêntica de `matlab/volta_sintetica.mif`) |
| `volta_sintetica.hex` | Intel HEX-32 (Quartus `INIT_FILE` / modelo `altsyncram`) |
| `volta_sintetica.txt` | Uma palavra hex por linha, sem `@endereço` (`$readmemh` / textio) |

`stim/` é a pasta canônica. `matlab/` é o workspace do gerador.
