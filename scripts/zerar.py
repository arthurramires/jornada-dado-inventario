import shutil
import sys
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[1]
CAMADAS = ["bronze", "silver", "gold", "quarentena"]
AVULSOS = [
    RAIZ / "data" / "analytics.duckdb",
    RAIZ / "data" / "analytics.duckdb.wal",
    RAIZ / "dbt" / "target",
]


def alvos() -> list[Path]:
    encontrados = []
    for camada in CAMADAS:
        pasta = RAIZ / "data" / camada
        if pasta.exists():
            encontrados += [p for p in sorted(pasta.iterdir()) if p.name != ".gitkeep"]
    encontrados += [p for p in AVULSOS if p.exists()]
    return encontrados


def main() -> None:
    lista = alvos()
    if not lista:
        print("As camadas já estão vazias.")
        return

    print("Vai apagar:\n")
    for caminho in lista:
        print(f"  {caminho.relative_to(RAIZ)}")
    print("\ndata/raw/ não é tocado.")

    if "--sim" not in sys.argv:
        resposta = input(f"\nConfirma apagar {len(lista)} item(ns)? [s/N] ").strip().lower()
        if resposta not in ("s", "sim"):
            print("Cancelado.")
            return

    for caminho in lista:
        if caminho.is_dir():
            shutil.rmtree(caminho)
        else:
            caminho.unlink()

    for camada in CAMADAS:
        pasta = RAIZ / "data" / camada
        pasta.mkdir(parents=True, exist_ok=True)
        (pasta / ".gitkeep").touch()

    print("\nPronto. Para reconstruir:")
    print("  python -m src.pipeline")
    print("  cd dbt && dbt build")


if __name__ == "__main__":
    main()
