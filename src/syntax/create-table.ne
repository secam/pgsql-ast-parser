@lexer lexerAny
@include "base.ne"


# https://www.postgresql.org/docs/12/sql-createtable.html
createtable_statement -> %kw_create %kw_table kw_ifnotexists:? (ident dot {% get(0) %}):? word lparen createtable_declarationlist rparen
     {% x => {

        const cols = x[6].filter((v: any) => 'dataType' in v);
        const constraints = x[6].filter((v: any) => !('dataType' in v));

        return {
            type: 'create table',
            ... !!x[2] ? { ifNotExists: true } : {},
            ... !!x[3] ? { schema: x[3] } : {},
            name: x[4],
            columns: cols,
            ...constraints.length ? { constraints } : {},
        }
    } %}



createtable_declarationlist -> createtable_declaration (comma createtable_declaration {% last %}):* {% ([head, tail]) => {
    return [head, ...(tail || [])];
} %}

createtable_declaration -> (createtable_constraint | createtable_column) {% unwrap %}

# ================= TABLE CONSTRAINT =======================
createtable_named_constraint[CST]
    -> (%kw_constraint word {% last %}):? $CST {% x => {
        const name = unwrap(x[0]);
        if (!name) {
            return unwrap(x[1]);
        }
        return {
            constraintName: name,
            ...unwrap(x[1]),
        }
    } %}

# see "table_constraint" section of doc
createtable_constraint -> createtable_named_constraint[createtable_constraint_def] {% unwrap %}


createtable_constraint_def
    -> createtable_constraint_def_unique
    | createtable_constraint_def_check
    | createtable_constraint_foreignkey

createtable_constraint_def_unique
    -> (%kw_unique | kw_primary_key) lparen createtable_collist rparen {% x => ({
        type: flattenStr(x[0]).join(' ').toLowerCase(),
        columns: x[2],
    }) %}

createtable_constraint_def_check
     -> %kw_check expr_paren {% ([_, expr]) => ({
         type: 'check',
         expr: unwrap(expr),
     }) %}

createtable_constraint_foreignkey
    -> %kw_foreign kw_key collist_paren
            %kw_references ident collist_paren
            (%kw_on kw_delete createtable_constraint_on_action {% last %}):?
            (%kw_on kw_update createtable_constraint_on_action {% last %}):?
        {% x => ({
            type: 'foreign key',
            localColumns: x[2],
            foreignTable: unwrap(x[4]),
            foreignColumns: x[5],
            onDelete: x[6] || 'no action',
            onUpdate: x[7] || 'no action',
        }) %}

createtable_constraint_on_action
    -> (kw_cascade
    | (kw_no kw_action)
    | kw_restrict
    | kw_set (%kw_null | %kw_default))
    {% x => flattenStr(x).join(' ').toLowerCase() %}


# ================ COLUMN ======================
createtable_collist -> ident (comma ident {% last %}):* {% ([head, tail]) => {
    return [head, ...(tail || [])];
} %}


createtable_column -> word data_type createtable_collate:? createtable_column_constraint:* {% x => {
    return {
        name: x[0],
        dataType: x[1],
        ...x[2] ? { collate: x[2] }: {},
        ...x[3] && x[3].length ? { constraints: x[3] }: {},
    }
} %}


# ======================== COLUMN CONSTRAINT =================================

createtable_column_constraint
    -> createtable_named_constraint[createtable_column_constraint_def] {% unwrap %}

# todo handle advanced constraints (see doc)
createtable_column_constraint_def
    -> %kw_unique       {% () => ({ type: 'unique' }) %}
    | kw_primary_key    {% () => ({ type: 'primary key' }) %}
    | kw_not_null       {% () => ({ type: 'not null' }) %}
    | %kw_null          {% () => ({ type: 'null' }) %}
    | %kw_default expr  {% ([_, e]) => ({ type: 'default', default: unwrap(e) }) %}
    | %kw_check expr_paren {% ([_, e]) => ({ type: 'check', expr: unwrap(e) }) %}

createtable_collate
    -> %kw_collate (ident dot {% get(0) %}):? ident {% ([_, schema, collation]) => {
        return {
            schema,
            collation,
        };
    }%}