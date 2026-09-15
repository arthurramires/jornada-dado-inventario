-- Garante o grão da fato: o mesmo bem não pode aparecer duas vezes no mesmo exercício.
select
    exercicio,
    numero_patrimonio,
    count(*) as linhas
from {{ ref('fato_bem_inventariado') }}
group by exercicio, numero_patrimonio
having count(*) > 1
