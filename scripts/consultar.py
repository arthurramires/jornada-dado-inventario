import os
import sys
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parents[1]


def comandos(sql: str) -> list[str]:
    partes = []
    for bloco in sql.split(";"):
        codigo = [linha for linha in bloco.splitlines() if linha.strip() and not linha.strip().startswith("--")]
        if codigo:
            partes.append(bloco)
    return partes


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("uso: python scripts/consultar.py consultas/resposta.sql")

    arquivo = Path(sys.argv[1]).resolve()
    os.chdir(RAIZ)
    con = duckdb.connect()
    for comando in comandos(arquivo.read_text(encoding="utf-8")):
        titulo = next((l.strip("- ").strip() for l in comando.splitlines() if l.startswith("-- ")), "")
        if titulo:
            print(f"\n{titulo}")
        con.sql(comando).show(max_rows=60, max_width=250)


if __name__ == "__main__":
    main()
