{{ config(location='../data/silver/stg_leituras.parquet') }}

with fonte as (

    select * from {{ source('bronze', 'leituras_coleta') }}

),

de_para as (

    select * from {{ ref('de_para_origem_leitura') }}

),

tipada as (

    select
        trim(id_leitura) as id_leitura,
        try_cast(exercicio as integer) as exercicio,

        -- O leitor de código de barras completa com zeros e a digitação traz espaço e ponto.
        -- Mesmo tratamento da carga, para os dois lados do join ficarem iguais.
        try_cast(nullif(regexp_replace(numero_patrimonio, '[^0-9]', '', 'g'), '') as bigint) as numero_patrimonio,

        try_cast(local_codigo_area as integer) as codigo_area,
        trim(local_espaco_fisico) as espaco_fisico,

        -- O app manda ISO; leitura lançada pelo backoffice vem como "05/08/2026 14:03".
        coalesce(
            try_cast(coletado_em as timestamp),
            try_strptime(coletado_em, '%d/%m/%Y %H:%M')
        ) as coletado_em,

        coalesce(nullif(lower(trim(origem_leitura)), ''), 'nao_informada') as origem_recebida,

        _arquivo_origem as lote

    from fonte

),

-- Quando a sincronização offline cai no meio, o app reenvia as leituras e elas aparecem de
-- novo no lote seguinte com o mesmo id_leitura. Fica a primeira chegada.
sem_reenvio as (

    select *
    from tipada
    qualify row_number() over (partition by id_leitura order by lote) = 1

)

-- O login do coletor fica no Bronze e não passa daqui. A pergunta não precisa saber quem leu,
-- e dado pessoal que não é usado não deve circular pelas camadas.
select
    s.id_leitura,
    s.exercicio,
    s.numero_patrimonio,
    s.codigo_area,
    s.espaco_fisico,
    s.coletado_em,
    s.origem_recebida,
    -- O domínio da origem mudou com o tempo: "scanner" era o nome antigo da câmera do celular
    -- (hoje "celular") e o app PWA manda "mobile_*". O de-para está num seed para a regra morar
    -- num lugar só.
    d.origem_leitura,
    d.tipo_captura,
    s.lote
from sem_reenvio s
left join de_para d on d.origem_recebida = s.origem_recebida
