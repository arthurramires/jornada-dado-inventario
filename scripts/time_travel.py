import argparse
from datetime import datetime
from pathlib import Path

import duckdb
from deltalake import DeltaTable

RAIZ = Path(__file__).resolve().parents[1]

CONSULTA = """
select
    exercicio,
    count(*) as leituras,
    count(distinct _arquivo_origem) as lotes,
    max(_ingerido_em) as ultima_ingestao
from tabela
group by exercicio
order by exercicio
"""


def mostrar_historico(caminho: Path) -> int:
    historico = sorted(DeltaTable(str(caminho)).history(), key=lambda c: c["version"])
    print(f"Histórico de {caminho.relative_to(RAIZ)}\n")
    for commit in historico:
        quando = datetime.fromtimestamp(commit["timestamp"] / 1000).strftime("%d/%m/%Y %H:%M:%S")
        print(f"  versão {commit['version']}  {quando}  {commit['operation']:<6} {commit.get('arquivo_origem', '')}")
    return historico[-1]["version"]


def consultar(caminho: Path, versao: int):
    tabela = DeltaTable(str(caminho), version=versao).to_pyarrow_table()
    return duckdb.sql(CONSULTA).fetchall(), duckdb.sql(CONSULTA).columns


def imprimir(titulo: str, linhas, colunas) -> None:
    print(f"\n{titulo}")
    print("  " + " | ".join(colunas))
    for linha in linhas:
        print("  " + " | ".join(str(v) for v in linha))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tabela", default="leituras_coleta")
    parser.add_argument("--versao", type=int)
    args = parser.parse_args()

    caminho = RAIZ / "data" / "bronze" / args.tabela
    atual = mostrar_historico(caminho)
    anterior = args.versao if args.versao is not None else max(atual - 1, 0)

    imprimir(f"Versão {anterior}", *consultar(caminho, anterior))
    imprimir(f"Versão {atual} (atual)", *consultar(caminho, atual))


if __name__ == "__main__":
    main()
