import hashlib
import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
from deltalake import CommitProperties, DeltaTable, write_deltalake
from dotenv import load_dotenv

RAIZ = Path(__file__).resolve().parents[1]
load_dotenv(RAIZ / ".env")

DATA_RAW_PATH = RAIZ / os.getenv("DATA_RAW_PATH", "data/raw")
DATA_BRONZE_PATH = RAIZ / os.getenv("DATA_BRONZE_PATH", "data/bronze")

logger = logging.getLogger(__name__)


def hash_arquivo(caminho: Path) -> str:
    return hashlib.sha256(caminho.read_bytes()).hexdigest()


def commits(tabela: Path) -> list[dict]:
    if not DeltaTable.is_deltatable(str(tabela)):
        return []
    return sorted(DeltaTable(str(tabela)).history(), key=lambda c: c["version"])


def ja_ingerido(tabela: Path, hash_: str, modo: str) -> bool:
    historico = commits(tabela)
    if not historico:
        return False
    if modo == "overwrite":
        return historico[-1].get("hash_arquivo") == hash_
    return any(c.get("hash_arquivo") == hash_ for c in historico)


def como_texto(valor):
    if isinstance(valor, dict):
        return {chave: como_texto(v) for chave, v in valor.items()}
    if valor is None:
        return None
    return str(valor)


def ler_areas(arquivo: Path) -> pd.DataFrame:
    return pd.read_excel(arquivo, dtype=str)


def ler_carga_patrimonial(arquivo: Path) -> pd.DataFrame:
    return pd.read_csv(arquivo, sep=";", dtype=str, encoding="latin-1", keep_default_na=False)


def ler_leituras(arquivo: Path) -> pd.DataFrame:
    payload = json.loads(arquivo.read_text(encoding="utf-8"))
    registros = [como_texto(r) for r in payload["leituras"]]
    return pd.json_normalize(registros, sep="_")


def gravar_bronze(df: pd.DataFrame, tabela: Path, arquivo: Path, hash_: str, modo: str) -> None:
    df = df.astype("string")
    df["_arquivo_origem"] = arquivo.name
    df["_ingerido_em"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    tabela.parent.mkdir(parents=True, exist_ok=True)
    write_deltalake(
        str(tabela),
        df,
        mode=modo,
        schema_mode="merge" if modo == "append" else "overwrite",
        commit_properties=CommitProperties(
            custom_metadata={"arquivo_origem": arquivo.name, "hash_arquivo": hash_}
        ),
    )
    versao = DeltaTable(str(tabela)).version()
    logger.info("%s <- %s: %d registros (versão %d)", tabela.name, arquivo.name, len(df), versao)


def ingerir(nome: str, arquivos: list[Path], leitor, modo: str, destino: Path | None = None) -> int:
    tabela = (destino or DATA_BRONZE_PATH) / nome
    gravados = 0
    for arquivo in arquivos:
        hash_ = hash_arquivo(arquivo)
        if ja_ingerido(tabela, hash_, modo):
            logger.info("%s <- %s: sem mudança, nada a gravar", nome, arquivo.name)
            continue
        gravar_bronze(leitor(arquivo), tabela, arquivo, hash_, modo)
        gravados += 1
    return gravados


def ingest_areas(origem: Path | None = None, destino: Path | None = None) -> int:
    raw = origem or DATA_RAW_PATH
    return ingerir("areas", [raw / "areas.xlsx"], ler_areas, "overwrite", destino)


def ingest_carga_patrimonial(origem: Path | None = None, destino: Path | None = None) -> int:
    raw = origem or DATA_RAW_PATH
    return ingerir("carga_patrimonial", [raw / "carga_patrimonial.csv"], ler_carga_patrimonial, "overwrite", destino)


def ingest_leituras(origem: Path | None = None, destino: Path | None = None) -> int:
    raw = origem or DATA_RAW_PATH
    lotes = sorted((raw / "leituras").glob("*.json"))
    return ingerir("leituras_coleta", lotes, ler_leituras, "append", destino)
