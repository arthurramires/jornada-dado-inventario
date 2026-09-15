-- Cada bem cai em exatamente uma situação. Se a soma dos indicadores não der 1, a taxa sai errada.
select
    exercicio,
    numero_patrimonio
from {{ ref('fato_bem_inventariado') }}
where localizado_na_area + localizado_em_outra_area + nao_localizado <> 1
