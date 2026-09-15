{{ config(location='../data/quarentena/leituras_rejeitadas.parquet') }}

-- Leituras que não conseguimos ligar a um bem ativo da carga do exercício.
-- Elas não são descartadas. No inventário, leitura sem carga é um achado: plaqueta sem cadastro,
-- número digitado errado ou bem que chegou sem tombamento. Alguém da Coordenadoria precisa
-- olhar cada uma, que é o mesmo papel dos itens pendentes de aprovação no módulo novo.

with leituras as (

    select * from {{ ref('stg_leituras') }}

),

carga as (

    select distinct
        exercicio,
        numero_patrimonio
    from {{ ref('stg_carga_patrimonial') }}
    where situacao_bem = 'ATIVO'

)

select
    l.id_leitura,
    l.exercicio,
    l.numero_patrimonio,
    l.codigo_area,
    l.espaco_fisico,
    l.coletado_em,
    l.origem_leitura,
    case
        when l.numero_patrimonio is null then 'patrimonio_ausente'
        else 'fora_da_carga'
    end as motivo,
    l.lote
from leituras l
left join carga c
    on c.exercicio = l.exercicio
   and c.numero_patrimonio = l.numero_patrimonio
where c.numero_patrimonio is null
