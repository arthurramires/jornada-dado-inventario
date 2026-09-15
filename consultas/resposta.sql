-- 1. Taxa de localização por exercício
select
    f.exercicio,
    count(*)                                                as bens_em_carga,
    sum(f.localizado_na_area)                               as localizados,
    sum(f.localizado_em_outra_area)                         as em_outra_area,
    sum(f.nao_localizado)                                   as nao_localizados,
    round(100.0 * sum(f.localizado_na_area) / count(*), 1)  as taxa_localizacao_pct,
    sum(f.valor_nao_localizado)                             as valor_nao_localizado
from 'data/gold/fato_bem_inventariado.parquet' f
group by f.exercicio
order by f.exercicio;

-- 2. Taxa de localização por região e comarca
select
    f.exercicio,
    a.regiao,
    a.comarca,
    count(*)                                                as bens_em_carga,
    sum(f.localizado_na_area)                               as localizados,
    sum(f.localizado_em_outra_area)                         as em_outra_area,
    sum(f.nao_localizado)                                   as nao_localizados,
    round(100.0 * sum(f.localizado_na_area) / count(*), 1)  as taxa_localizacao_pct,
    sum(f.valor_nao_localizado)                             as valor_nao_localizado
from 'data/gold/fato_bem_inventariado.parquet' f
join 'data/gold/dim_area.parquet' a on a.area_id = f.area_carga_id
group by f.exercicio, a.regiao, a.comarca
order by f.exercicio, taxa_localizacao_pct;
