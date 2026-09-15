import shutil

import pandas as pd
import pytest
from deltalake import DeltaTable

from src import ingest

RAW = ingest.DATA_RAW_PATH


@pytest.fixture
def bronze(tmp_path):
    return tmp_path / "bronze"


def test_carga_preserva_todas_as_linhas_da_origem(bronze):
    ingest.ingest_carga_patrimonial(destino=bronze)
    origem = pd.read_csv(RAW / "carga_patrimonial.csv", sep=";", dtype=str, encoding="latin-1")
    gravado = DeltaTable(str(bronze / "carga_patrimonial")).to_pandas()
    assert len(gravado) == len(origem)


def test_bronze_guarda_o_texto_como_chegou(bronze):
    ingest.ingest_carga_patrimonial(destino=bronze)
    gravado = DeltaTable(str(bronze / "carga_patrimonial")).to_pandas()
    assert gravado["valor_atual"].str.contains(",").any()
    assert gravado["numero_patrimonio"].str.contains(r"\.").any()


def test_json_de_leituras_vira_colunas_com_metadado_de_ingestao(bronze):
    ingest.ingest_leituras(destino=bronze)
    colunas = DeltaTable(str(bronze / "leituras_coleta")).to_pandas().columns
    for coluna in ["id_leitura", "numero_patrimonio", "local_codigo_area", "coletor", "_arquivo_origem", "_ingerido_em"]:
        assert coluna in colunas


def test_cada_lote_de_leituras_vira_uma_versao(bronze):
    ingest.ingest_leituras(destino=bronze)
    lotes = sorted((RAW / "leituras").glob("*.json"))
    assert DeltaTable(str(bronze / "leituras_coleta")).version() == len(lotes) - 1


def test_rodar_de_novo_nao_cria_versao(bronze):
    ingest.ingest_areas(destino=bronze)
    ingest.ingest_leituras(destino=bronze)
    assert ingest.ingest_areas(destino=bronze) == 0
    assert ingest.ingest_leituras(destino=bronze) == 0


def test_arquivo_alterado_gera_versao_nova(bronze, tmp_path):
    raw = tmp_path / "raw"
    shutil.copytree(RAW, raw)
    ingest.ingest_carga_patrimonial(origem=raw, destino=bronze)
    with open(raw / "carga_patrimonial.csv", "a", encoding="latin-1") as arquivo:
        arquivo.write("2026;999999;Cadeira giratória com braços;1101;310,00;ATIVO\r\n")
    assert ingest.ingest_carga_patrimonial(origem=raw, destino=bronze) == 1
    assert DeltaTable(str(bronze / "carga_patrimonial")).version() == 1
