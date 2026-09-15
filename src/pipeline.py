import logging
import os

from src import ingest

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"), format="[%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)


def main() -> None:
    logger.info("Ingestão: data/raw -> data/bronze (Delta)")

    etapas = [
        ingest.ingest_areas,
        ingest.ingest_carga_patrimonial,
        ingest.ingest_leituras,
    ]
    gravados = sum(etapa() for etapa in etapas)

    logger.info("Fim da ingestão. %d commit(s) novo(s) no Bronze.", gravados)
    logger.info("Próximo passo: cd dbt && dbt build")


if __name__ == "__main__":
    main()
