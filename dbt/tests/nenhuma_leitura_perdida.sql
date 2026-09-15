-- Nenhuma leitura some no caminho: ou ela casa com um bem da fato, ou está na quarentena.
select l.id_leitura
from {{ ref('stg_leituras') }} l
left join {{ ref('fato_bem_inventariado') }} f
    on f.exercicio = l.exercicio
   and f.numero_patrimonio = l.numero_patrimonio
left join {{ ref('qrt_leituras_rejeitadas') }} q
    on q.id_leitura = l.id_leitura
where f.numero_patrimonio is null
  and q.id_leitura is null
