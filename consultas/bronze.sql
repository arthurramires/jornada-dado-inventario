-- 1. O Bronze guarda a carga como chegou: número com máscara ou zeros e valor em formato brasileiro
select
    numero_patrimonio,
    valor_atual,
    situacao_bem,
    _arquivo_origem
from delta_scan('data/bronze/carga_patrimonial')
where numero_patrimonio like '%.%' or numero_patrimonio like '00%'
limit 5;

-- 2. E as leituras com todas as origens que o app já mandou
select
    origem_leitura,
    count(*) as leituras
from delta_scan('data/bronze/leituras_coleta')
group by origem_leitura
order by leituras desc;
