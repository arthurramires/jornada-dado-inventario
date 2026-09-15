{% macro nome_proprio(coluna) -%}
array_to_string(
    list_transform(
        string_split(lower(trim(regexp_replace({{ coluna }}, '\s+', ' ', 'g'))), ' '),
        lambda p: case when p in ('de', 'da', 'do', 'das', 'dos', 'e') then p else upper(p[1]) || p[2:] end
    ),
    ' '
)
{%- endmacro %}
