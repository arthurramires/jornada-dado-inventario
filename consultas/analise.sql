-- 3. Critério do SGM antigo x critério do módulo novo, por comarca
select
    f.exercicio,
    a.comarca,
    count(*)                                                                         as bens_em_carga,
    round(100.0 * sum(f.localizado_na_area + f.localizado_em_outra_area) / count(*), 1) as taxa_criterio_sgm_pct,
    round(100.0 * sum(f.localizado_na_area) / count(*), 1)                            as taxa_criterio_novo_pct
from 'data/gold/fato_bem_inventariado.parquet' f
join 'data/gold/dim_area.parquet' a on a.area_id = f.area_carga_id
group by f.exercicio, a.comarca
order by f.exercicio, taxa_criterio_sgm_pct - taxa_criterio_novo_pct desc;

-- 4. Para onde foram os bens encontrados fora do lugar (a dim_area nos dois papéis)
select
    f.exercicio,
    carga.nome_area                    as area_da_carga,
    leitura.nome_area                  as area_onde_foi_lido,
    sum(f.localizado_em_outra_area)    as bens
from 'data/gold/fato_bem_inventariado.parquet' f
join 'data/gold/dim_area.parquet' carga   on carga.area_id   = f.area_carga_id
join 'data/gold/dim_area.parquet' leitura on leitura.area_id = f.area_leitura_id
group by all
having sum(f.localizado_em_outra_area) > 0
order by f.exercicio, bens desc
limit 15;

-- 5. Como os bens foram lidos, por exercício
select
    f.exercicio,
    o.tipo_captura,
    o.origem_leitura,
    count(*) as bens
from 'data/gold/fato_bem_inventariado.parquet' f
join 'data/gold/dim_origem_leitura.parquet' o on o.origem_leitura = f.origem_leitura
group by all
order by f.exercicio, bens desc;

-- 6. Leituras na quarentena, por motivo e lote
select
    motivo,
    lote,
    count(*) as leituras
from 'data/quarentena/leituras_rejeitadas.parquet'
group by all
order by lote, motivo;
