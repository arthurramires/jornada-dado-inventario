-- Grão: um bem ativo na carga de uma área, em um exercício de inventário (exercicio + numero_patrimonio).
--
-- Fica de fora: bem com situação BAIXADO na carga, porque não é cobrado no inventário, e leitura
-- que não casa com nenhum bem da carga, que vai para a quarentena. O total de linhas é o total de
-- bens que a área precisava encontrar, e não o total de leituras.

{{ config(location='../data/gold/fato_bem_inventariado.parquet') }}

with carga as (

    select *
    from {{ ref('stg_carga_patrimonial') }}
    where situacao_bem = 'ATIVO'

),

areas as (

    select area_id from {{ ref('dim_area') }}

),

leituras_validas as (

    select l.*
    from {{ ref('stg_leituras') }} l
    anti join {{ ref('qrt_leituras_rejeitadas') }} q on q.id_leitura = l.id_leitura

),

-- Um bem pode ser lido mais de uma vez no mesmo inventário. Vale a última leitura: é o que o
-- fluxo de coleta faz quando o servidor escolhe ATUALIZAR um registro já coletado, e é a
-- informação mais recente de onde o bem está.
ultima_leitura as (

    select
        exercicio,
        numero_patrimonio,
        codigo_area,
        origem_leitura,
        coletado_em,
        count(*) over (partition by exercicio, numero_patrimonio) as quantidade_leituras
    from leituras_validas
    qualify row_number() over (
        partition by exercicio, numero_patrimonio
        order by coletado_em desc, id_leitura desc
    ) = 1

),

bens as (

    select
        c.exercicio,
        c.numero_patrimonio,
        c.codigo_area_carga,
        c.valor_atual,
        u.codigo_area as codigo_area_leitura,
        u.origem_leitura,
        u.coletado_em,
        u.quantidade_leituras
    from carga c
    left join ultima_leitura u
        on u.exercicio = c.exercicio
       and u.numero_patrimonio = c.numero_patrimonio

)

select
    exercicio,
    numero_patrimonio,

    -- Área que não está na planilha aponta para a linha -1 da dim_area (ver dim_area.sql).
    case when codigo_area_carga in (select area_id from areas) then codigo_area_carga else -1 end as area_carga_id,
    case
        when codigo_area_leitura is null then null
        when codigo_area_leitura in (select area_id from areas) then codigo_area_leitura
        else -1
    end as area_leitura_id,

    origem_leitura,

    -- A decisão que mais mexe no número: bem lido em outra área NÃO conta como localizado.
    -- O SGM antigo contava qualquer bem lido como inventariado; o módulo novo só conta quando a área
    -- da leitura é a área da carga. Bem fora do lugar é bem que a carga não sabe onde está,
    -- e corrigir isso é o motivo de existir inventário. "Em outra área" fica numa situação própria
    -- para o gestor enxergar a diferença entre os dois critérios.
    case
        when codigo_area_leitura is null then 'Não localizado'
        when codigo_area_leitura = codigo_area_carga then 'Localizado'
        else 'Localizado em outra área'
    end as situacao_inventario,

    -- Indicadores 0/1 em vez de percentual pronto: percentual não soma. A taxa de uma região não é
    -- a média das taxas das comarcas, então ela é calculada na consulta a partir destas colunas.
    case when codigo_area_leitura = codigo_area_carga then 1 else 0 end as localizado_na_area,
    case when codigo_area_leitura <> codigo_area_carga then 1 else 0 end as localizado_em_outra_area,
    case when codigo_area_leitura is null then 1 else 0 end as nao_localizado,

    coalesce(quantidade_leituras, 0) as quantidade_leituras,
    cast(coletado_em as date) as data_ultima_leitura,

    valor_atual,
    case when codigo_area_leitura is null then valor_atual else 0 end as valor_nao_localizado

from bens
