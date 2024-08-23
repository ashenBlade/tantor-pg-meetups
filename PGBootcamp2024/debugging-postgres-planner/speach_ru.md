# Отлаживаем планировщик Postgres

## Высокоуровневая архитектура планировщика

### Алгоритм обработки запроса

В начале вспомним процесс обработки запроса. Алгоритм можно представить в виде 4
этапов:

1. Парсинг запроса
2. Переписывание запроса
3. Работа планировщика
4. Исполнение запроса

Сегодня поговорим именно о 3 этапе – работе планировщика.

TODO: схема: обработка запроса

### Устройство планировщика

Рассмотрим общий вид на то, как работает планировщик.
Его работу можно поделить на несколько (TODO: конкретное число) этапов:

TODO: вместо предобработка какое-нибудь другое слово

1. Предобработка дерева запроса
2. Оптимизация
3. Нахождение возможных путей выполнения
4. Выбор наиболее оптимального плана выполнения

Первые 2 этапа – это оптимизации. Разница заключается в том, что в 1 этапе мы
работаем только с деревом запроса и выполняем простые оптимизации, например,
constant folding (вычисляем выражения с константными значениями). А во 2 этапе
применяются уже более сложные оптимизации. Как правило они связаны со знаниями
о всем запросе (join'ы, TODO: добавить)

3 этап – мы находим все возможные пути выполнения запроса, используя знания
полученные после всех оптимизаций.

Последний 4 этап – строим план выполнения из самого дешевого пути.

TODO: схема: этапы планировщика

### Организация в исходном коде

Говоря об исходном коде, это организовано следующим образом.

- `query_planner` – планировщик для создания путей доступа к самим таблицам,
    т.е. создает узлы Scan методов (SeqScan, IndexScan и т.д.)
- `grouping_planner` – обертка над `query_planner`, ответственная за добавление
    логики постобработки кортежей (сортировка, группировка). Грубо говоря,
    декорирует узлы чтения нужной логикой
- `subquery_planner` – входная точка для планирования 1 запроса: подготавливает
    запрос для `grouping_planner` и вызывает его
- `standard_planner` – входная точка самого планировщика

Схематично, это можно отобразить так.

На самом верху имеется `standard_planner`. Он подготавливает окружение и после
вызывает `subquery_planner` для самого высокоуровнего запроса.

`subquery_planner`: предобрабатывает *дерево запроса* и вызывает
`grouping_planner` для анализа всего запроса, а после создает план для самого
дешевого пути.

`grouping_planner`: отвечает за логику обработки прочитанных кортежей:
сортировка, группировка, оконные функции и т.д.

`query_planner`: инициализирует состояние планировщика и находит возможные
методы доступа к таблице.

```c
standard_planner()
{
    /* Initialize global state */
    subquery_planner()
    {
        /* Parse tree preprocessing */
        grouping_planner()
        {
            /* Setup grouping operations support */
            query_planner()
            {
                /* Setup planner info */
                /* Create Scan path */
            }
            /* Decorate with sort/agg/window/... paths */
        }
        /* Select cheapest path */
    }
    /* Create plan for whole query */
}
```

`subquery_planner` - запускается для каждого обнаруженного подзапроса, причем
верхнеуровневый запрос - тоже подзапрос, просто у него не родителя.

TODO: схема: дерево запроса и доп указатели какие функции ответственны

## Используемые структуры данных

Теперь поговорим о структурах данных.

### Узлы и деревья

Многие структуры данных в Postgres являются узлами - `Node`. Первое поле у
каждого узла - это `NodeTag`, дискриминатор типа. Это простой enum, который
составляется как префикс `T_` + название типа.

Все возможные узлы уже известны и их значения определяются в `src/include/nodes/node.h`,
либо, начиная с 16 версии автоматически генерируются в `src/include/nodes/nodetags.h`.

TODO: файлы с реализациями

### Какие бывают узлы

На этой схеме представлено дерево этих узлов. Все не уместились - их 474, поэтому
рассмотрим основные.

TODO: схема: узлы, корень Node и от него идут другие (контейнеры, Expr и т.д.)

`List` - это динамический массив. Хранить он может в себе `Node *`, `int`,
`Oid` или `TransactionId`, но только одного типа. Достигается это тем, что
у списка есть отдельный тэг для каждого типа:

| Тип             | Тэг         |
| --------------- | ----------- |
| `Node *`        | `T_List`    |
| `int`           | `T_IntList` |
| `Oid`           | `T_OidList` |
| `TransactionId` | `T_XidList` |

Но при этом, название типа одно и то же - `List`.

`Bitmapset` - это множество чисел.

`Expr` - это базовый тип для узлов, которые могут быть выполнены. Примеры:

| Тип        | Описание             | Результат выполнения             |
| ---------- | -------------------- | -------------------------------- |
| `Var`      | Атрибут таблицы      | Значение атрибута из кортежа     |
| `Const`    | Константа            | Значение константы               |
| `OpExpr`   | Оператор             | Вызов оператора с аргументами    |
| `FuncExpr` | Функция              | Вызор функции с аргументами      |
| `BoolExpr` | Логическое выражение | Выполнение логического выражения |
| `SubPlan`  | Подзапрос            | Результат запроса                |

> `Node` и `Expr` - это псевдоузлы, в том понимании, что у них нет своего тэга.
> Они служат только маркерами: `Node` - это узел, `Expr` - это вычисляемый узел.

### Структуры данных планировщика

Теперь поговорим о представлении запроса в коде.

Весь запрос - это множество подзапросов. Даже если их нет, то весь запрос - это
один большой подзапрос.

`PlannerGlobal` - хранит информацию о всем запросе. Создается в самом начале -
`standard_planner`.

`PlannerInfo` - хранит информацию об одном подзапросе. Создается в `subquery_planner`.

На схеме изображено отношение между запросами и подзапросами.

TODO: схема: запрос и какие структуры ответственны за эти части

Дальше поговорим об источнике данных.

Грубо говоря, все, что находится во `FROM` - это Range Table. Range Table - это
список используемых источников данных для запроса. Каждый элемент этого списка
называется Range Table Entry. Ими могут быть:

- Таблица
- Функция
- Другой подзапрос
- `JOIN`'ы
- CTE
- `VALUES`

TODO: добавить больше RTE примеров

`RangeTblEntry` - это структура, представляющая Range Table Entry.

На схеме изображены RTE, участвующие во `FROM`:

TODO: схема: range table + rte соотношение

`RelOptInfo` - это структура планировщика для RTE. Можно сказать, разница в том, что
`RangeTblEntry` больше про дерево запроса, а `RelOptInfo` - про планировщик.
Например, хранит в себе количество страниц или кортежей, стоимость путей.

`RestrictInfo` - представляет ограничение. Это может быть не только условие в
`WHERE`, но и условие `JOIN`, либо ограничения таблицы (`CONSTRAINT`).

## Реализуем Constraint Exclusion

Constraint Exclusion - это оптимизация, которая учитывает наложенные ограничения:
на запрос, на таблицу, на значения и т.д.

Предлагаю реализовать нечто подобное в Postgres.

### Постановка задачи

Для конкретики - мы хотим учитывать допустимый диапазон возможных значений.
Например, если в `WHERE` имеется `AND` со сравнениями атрибутов, то этот атрибут
не может быть одновременно больше и не больше определенной константы. Вот этим
и займемся.

TODO: схема: запрос с WHERE -> пустой ответ

### Проектируем решение

Для начала отобразим, то что мы хотим получить. Говоря в терминах узлов, такую
ситуацию можно определить следующим шаблоном.

TODO: схема: OpExpr->Var->Const

Таким образом мы ищем `AND`, у которого оба выражения - вызовы оператора, имеющие
разные только операторы (противоположные).Если мы обнаружили такой паттерн, то
можем сказать, что этот запрос можно убрать из рассмотрения - он ничего не вернет.

В примере, это численное сравнение - никакое число не может быть одновременно
и больше и не больше 0.

Для простоты будем искать только их - без `OR`, `NOT`, обнаружения перестановок
операндов и прочего. Только `AND`, атрибуты и константы со строгим порядком.

### Реализация

Для начала спроектируем базовую функцию - определение взаимоисключающих условий.
Тут нам понадобится знание об узлах.

Эта функция будет принимать на вход 2 `OpExpr` и возвращать `true`, если эти
выражения представляют взаимоисключающие условия.

Первым делом определим, что по обе стороны оператора - атрибут и константа.
Оператор - это тоже функция с аргументами. Аргументы хранятся в поле `args`.

Так как это бинарный оператор, то длина `args` должна равняться 2. Аргументы
следуют в порядке вызова.

```c++
List *args = expr->args;
if (list_length(args) != 2)
{
    return false;
}
```

Аргументы следуют в порядке вызова. В нашем случае первый аргумент должен быть
атрибутом, а второй - константой. Атрибут выражается узлом `Var`, а константа -
`Const`. Для проверки тэга узла используется макрос `IsA(nodeptr, type)`.
Проверку и получение `Var` и `Const` вынесем в отдельную функцию:

```c++
/* First element - attribute */
if (!IsA(linitial(args), Var))
{
    return false;
}
*out_var = (Var *) linitial(args);

/* Second element - constant */
if (!IsA(llast(args), Const))
{
    return false;
}
*out_const = (Const *) llast(args);
```

В итоге, функция для получения операндов выглядит следующим образом:

```c++
static bool
extract_operator_const_comp_expression(OpExpr *expr, Var **out_var, Const **out_const)
{
    List *args = expr->args;
    /* Check exactly 2 operands */
    if (list_length(args) != 2)
    {
        return false;
    }

    /* First element - attribute */
    if (!IsA(linitial(args), Var))
    {
        return false;
    }
    *out_var = (Var *) linitial(args);

    /* Second element - constant */
    if (!IsA(llast(args), Const))
    {
        return false;
    }

    *out_const = (Const *) llast(args);
    return true;
}
```

Теперь для каждого из выражений необходимо проверить, что соответствующие
операнды равны. Для сравнения узлов используется функция `equal`. На вход она
принимает 2 `void` указателя, но на самом деле работает только с узлами.

```c++
/* Attributes equal */
if (!equal(left_var, right_var))
{
    return false;
}

/* Constants equal */
if (!equal(left_const, right_const))
{
    return false;
}
```

Последний этап - проверка операндов. Мы воспользуемся системным каталогом
`pg_operator`. В заголовочном файле `utils/cache/lsyscache.c` находится
множество полезных и часто используемых функций для работы с системным
каталогом. Нас интересует функция `get_negator` - она по переданному `Oid`
оператора возвращает `Oid` соответствующего ему противоположного оператора.
Для `<` это будет `<=`.

```c++
/* Operators are opposite  */
return get_negator(left->opno) == right->opno || 
       left->opno == get_negator(right->opno);
```

В результате, функция выглядит таким образом:

```c
static bool
is_mutually_exclusive(OpExpr *left, OpExpr *right)
{
    Var *left_var;
    Const *left_const;
    Var *right_var;
    Const *right_const;

    /* Extract operands */
    if (!extract_operator_const_comp_expression(left, &left_var, &left_const))
    {
        return false;
    }
    if (!extract_operator_const_comp_expression(right, &right_var, &right_const))
    {
        return false;
    }
    
    /* Attributes equal */
    if (!equal(left_var, right_var))
    {
        return false;
    }
    
    /* Constants equal */
    if (!equal(left_const, right_const))
    {
        return false;
    }

    /* Operators are opposite  */
    return get_negator(left->opno) == right->opno || 
           left->opno == get_negator(right->opno);
}

```

Теперь осталось добавить эту логику в нужное место. Вначале добавим в этап
предобработки дерева запроса.

Первая часть `subquery_planner` - это предобработка дерева запроса с его
оптимизацией в возможным переписыванием. Нас интересует функция
`preprocess_expression` - это обобщенная функция, которая проходит по узлам и
выполняет общую предобработку: вычисление константных выражений, приведение к
каноническому виду и другие.

TODO: добавить вставки с кодом

Спускаясь ниже мы находим функцию `simplify_and_arguments` - она вызывается из
`preprocess_expression`, когда ей встречается узел `AND` условия, для проверки
того, что все выражение можно заменить константным `FALSE`.

Добавим нашу логику следующим образом (часть функции удалена для удобства):

```c
static List *
simplify_and_arguments(List *args,
                       eval_const_expressions_context *context,
                       bool *haveNull, bool *forceFalse)
{
    List *newargs = NIL;
    List *unprocessed_args;

    while (unprocessed_args)
    {
        Node *arg = (Node *) linitial(unprocessed_args);

        /* Omitted */

        if (IsA(arg, Const))
        {
            /* Omitted */
        }

        /* Compare current OpExpr with previous one for self-exclusion constraints */
        if (IsA(arg, OpExpr) && list_length(newargs) > 0 && IsA(llast(newargs), OpExpr))
        {
            if (is_mutually_exclusive((OpExpr *)arg, (OpExpr *)llast(newargs)))
            {
                *forceFalse = true;
                return NIL;
            }
        }
        
        newargs = lappend(newargs, arg);
    }

    return newargs;
}
```

Проверим результат. Представим, что у нас имеется подобная схема:

```sql
CREATE TABLE tbl(id INTEGER GENERATED ALWAYS AS IDENTITY, value INTEGER);
```

И тестовый запрос:

```sql
EXPLAIN ANALYZE SELECT id FROM tbl WHERE value > 0 AND value <= 0;
```

Для начала запустим запрос без наших изменений:

```text
                                          QUERY PLAN                                           
-----------------------------------------------------------------------------------------------
 Seq Scan on tbl  (cost=0.00..43.90 rows=11 width=4) (actual time=0.004..0.004 rows=0 loops=1)
   Filter: ((value > 0) AND (value <= 0))
 Planning Time: 0.186 ms
 Execution Time: 0.015 ms
(4 rows)
```

Видно, что мы действительно выполнили сканирование таблицы с примененным фильтром.
Теперь соберем вместе с нашими изменениями и запустим этот запрос:

```text
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.00 rows=0 width=0) (actual time=0.001..0.002 rows=0 loops=1)
   One-Time Filter: false
 Planning Time: 0.033 ms
 Execution Time: 0.013 ms
(4 rows)
```

По выводу видно, что весь запрос заменен пустым выводом:

- `Result` - узел возвращающий готовые значения
- `One-Time Filter: false` - единовременный фильтр, отклоняющий все записи

Но у этого подхода есть недостаток - он учитывает условия только в `WHERE`. Такой
запрос оптимизирован не будет:

```sql
SELECT id FROM tbl t1 JOIN tbl t2 ON t1.value > 0 WHERE t1.value <= 0;
```

Это может исправить планировщик, знающий о таких ограничениях. Следующее место,
куда мы добавим оптимизацию - в сам планировщик, сделаем эту оптимизацию частью
его работы.

Можно сказать, что работа планировщика начинается в `query_planner`, так как
там инициализируются поля `PlannerInfo`, необходимые для работы планировщика.
Нас интересует `simple_rel_array` - массив, который хранит в себе `RelOptInfo`.
Напомню, что `RelOptInfo` - это структура, представляющая информацию о таблице
или о `JOIN`'е. Все что нам нужно - пройтись по этому массиву и слить 2 таких
условия в один `FALSE`.

В `RelOptInfo` нам нужно работать с полем `baserestrictinfo` - список из
ограничений, наложенных на таблицу. Теперь нам необходимо пройтись по этому
массиву и удалить конфликтующие условия.

```c
void clamp_range_qualifiers(PlannerInfo *root)
{
    for (int i = 1; i < root->simple_rel_array_size; i++)
    {
        RelOptInfo *rel = root->simple_rel_array[i];
        if (rel == NULL || rel->rtekind != RTE_RELATION)
        {
            continue;
        }

        clamp_range_qualifier_for_rel(root, rel);
    }
}

static void
clamp_range_qualifier_for_rel(PlannerInfo *root, RelOptInfo *rel)
{
    ListCell *lc;
    List *new_baserestrictinfo;
    RestrictInfo *prev_rinfo;
    Index new_min_security;

    if (list_length(rel->baserestrictinfo) < 2)
    {
        return;
    }

    new_baserestrictinfo = NIL;
    prev_rinfo = NULL;
    new_min_security = rel->baserestrict_min_security;

    foreach (lc, rel->baserestrictinfo)
    {
        RestrictInfo *cur_rinfo = (RestrictInfo *)lfirst(lc);
        if (prev_rinfo == NULL)
        {
            prev_rinfo = cur_rinfo;
            continue;
        }

        if (IsA(prev_rinfo->clause, OpExpr) && IsA(cur_rinfo->clause, OpExpr) &&
            is_exclusive_range((OpExpr *)prev_rinfo->clause, (OpExpr *)cur_rinfo->clause))
        {
            RestrictInfo *false_rinfo = create_restrict_info_from_ops(root, prev_rinfo, cur_rinfo);
            prev_rinfo = false_rinfo;
            new_min_security = Min(new_min_security, false_rinfo->security_level);
        }
        else
        {
            new_baserestrictinfo = lappend(new_baserestrictinfo, prev_rinfo);
            prev_rinfo = cur_rinfo;
        }
    }

    if (prev_rinfo != NULL)
    {
        new_baserestrictinfo = lappend(new_baserestrictinfo, prev_rinfo);
    }

    
    pfree(rel->baserestrictinfo);
    rel->baserestrictinfo = new_baserestrictinfo;
    rel->baserestrict_min_security = new_min_security;
}
```

Добавим мы эту логику сразу после функции `add_base_rels_to_query`, которая
создает массив `RelOptInfo`.

Запускаем запрос и получаем следующий вывод:

```text
                                          QUERY PLAN                                           
-----------------------------------------------------------------------------------------------
 Seq Scan on tbl  (cost=0.00..43.90 rows=11 width=4) (actual time=0.007..0.008 rows=0 loops=1)
   Filter: ((value > 0) AND (value <= 0))
 Planning Time: 0.042 ms
 Execution Time: 0.020 ms
(4 rows)
```

Наш патч не сработал, планировщик все же решил использовать сканирование таблицы.
Причина этого следующая - практически все основные структуры как `PlannerInfo`
или `RelOptInfo` заполняются по мере работы, а не сразу. Мы предположили, что
раз `add_base_rels_to_query` создает этот массив, то и каждый элемент уже должен
быть проинициализирован, но это не так. Здесь ничего не остается кроме как
искать место, где данные будут инициализированы, добавлять `Assert` и писать
тесты.

В нашем случае, для исправления можно переместить вызов нашей функции вниз до
`make_one_rel`. Тогда все заработает:

```text
                                     QUERY PLAN                                     
------------------------------------------------------------------------------------
 Result  (cost=0.00..0.00 rows=0 width=0) (actual time=0.001..0.002 rows=0 loops=1)
   One-Time Filter: false
 Planning Time: 0.125 ms
 Execution Time: 0.012 ms
(4 rows)
```

Также в поле `baserestrictinfo` содержатся и ограничения связанные с `JOIN`'ами,
перемещением условий между подзапросами и другими оптимизациями планировщика.
Например, следующие запросы также дадут ожидаемый результат:

```sql
SELECT t1.id FROM tbl t1 JOIN tbl t2 ON t1.value > 0 WHERE t1.value <= 0;
SELECT t1.id FROM tbl t1 JOIN LATERAL (SELECT * FROM tbl t2 WHERE t1.value > 0) t2 ON TRUE WHERE t1.value <= 0;
SELECT t1.id FROM tbl t1 JOIN lateral (SELECT * FROM tbl JOIN (SELECT * FROM tbl WHERE t1.value > 0) t3 ON TRUE) t2 ON TRUE WHERE t1.value <= 0;
```

Но вот так удалять данные о запросе не самая лучшая идея, так как мы уменьшаем
известную нам информацию, а также тратим дополнительные ресурсы на эти операции.
Поэтому лучшим вариантом будет просто использовать эти знания непосредственно
при создании путей.

Вот мы и пришли к реализации в самом Postgres. Constraint Exclusion - это одна
из оптимизаций, которая включается GUC параметром `constraint_exclusion` и
проводится непосредственно перед вычислением стоимости пути. И там используется
примерно та же логика, что и наша. Например, вот кусок кода, обнаруживающий
противоположные операторы:

```c
static bool
operator_predicate_proof(Expr *predicate, Node *clause,
                         bool refute_it, bool weak)
{
    OpExpr *pred_opexpr,
           *clause_opexpr;
    Oid pred_collation,
        clause_collation;
    Oid pred_op,
        clause_op,
        test_op;
    Node *pred_leftop,
         *pred_rightop,
         *clause_leftop,
         *clause_rightop;

    /*
     * Both expressions must be binary opclauses, else we can't do anything.
     *
     * Note: in future we might extend this logic to other operator-based
     * constructs such as DistinctExpr.  But the planner isn't very smart
     * about DistinctExpr in general, and this probably isn't the first place
     * to fix if you want to improve that.
     */
    if (!is_opclause(predicate))
        return false;
    pred_opexpr = (OpExpr *) predicate;
    if (list_length(pred_opexpr->args) != 2)
        return false;
    if (!is_opclause(clause))
        return false;
    clause_opexpr = (OpExpr *) clause;
    if (list_length(clause_opexpr->args) != 2)
        return false;

    /*
     * If they're marked with different collations then we can't do anything.
     * This is a cheap test so let's get it out of the way early.
     */
    pred_collation = pred_opexpr->inputcollid;
    clause_collation = clause_opexpr->inputcollid;
    if (pred_collation != clause_collation)
        return false;

    /* Grab the operator OIDs now too.  We may commute these below. */
    pred_op = pred_opexpr->opno;
    clause_op = clause_opexpr->opno;

    /*
     * We have to match up at least one pair of input expressions.
     */
    pred_leftop = (Node *) linitial(pred_opexpr->args);
    pred_rightop = (Node *) lsecond(pred_opexpr->args);
    clause_leftop = (Node *) linitial(clause_opexpr->args);
    clause_rightop = (Node *) lsecond(clause_opexpr->args);

    if (equal(pred_leftop, clause_leftop))
    {
        if (equal(pred_rightop, clause_rightop))
        {
            /* We have x op1 y and x op2 y */
            return get_negator(pred_op) == clause_op;
        }
    }
    /* Omitted */
}
```

> Одно из различий в том, что мы не учитывали изменчивость функции. Нам следовало
> бы отбрасывать все `VOLATILE` операторы. Реальный код так делает.

## Советы как упростить себе жизнь при отладке

В конце, хотелось бы дать несколько советов как можно упростить себе жизнь, при
работе с планировщиком.

### Отключаем запрос пароля

При присоединении отладчика к другому процессу запрашивается пароль. Это
поведение можно отключить:

- В конфигурационном файле `/etc/sysctl.d/10-ptrace.conf` - необходимо выставить
    параметр `kernel.yama.ptrace_scope = 0`

- Записав `0` в файл `/proc/sys/kernel/yama/ptrace_scope`. Пример такой команды:
    `echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope`

Замечания:

- При 1 способе изменения вступят в силу после перезагрузки
- При 2 способе сразу, но придется выполнять эту команду постоянно

У себя я использую 1 способ, так удобнее.

### Выводим PID бэкэнда сразу

У `psql` есть конфигурационный файл `.psqlrc`. Все команды из него выполняются
каждый раз при запуске. Пример такого файла:

```sql
SELECT pg_backend_pid();
```

Через переменную окружения `PSQLRC` можно передать путь к `.psqlrc`. Пример:

```bash
PSQLRC="./build/.psqlrc" psql postgres
```

После запуска отобразится PID нашего бэкэнда.

### Параметры конфигурации

Существует несколько параметров конфигурации, полезных для отладки планировщика:

- `debug_print_parse`
- `debug_print_plan`
- `debug_print_rewritten`

Если параметр выставлен в `on`, то после соответствующего этапа в лог будут
выводиться дерево запроса, переписанное дерево запроса, созданный план. По факту,
они вызывают `pprint` - функцию, для вывода переданного узла в `stdout`. Ей и
самому можно пользоваться.

### Автоматизация

При работе с PostgreSQL можно выделить 4 основных этапов:

- Настройка (вызов `configure` скрипта)
- Сборка
- Запуск тестов
- Запуск БД и psql

Для каждого из этапов можно создать скрипты. Но большую выгоду мы можем получить,
если интегрируем эти скрипты в VS Code. Это можно сделать через таски - для
каждого скрипта создаем свои таски. Например, таска сборки может выглядеть таким
образом:

```json
{
    "label": "Build",
    "detail": "Build PostgreSQL and install into directory",
    "type": "shell",
    "command": "${workspaceFolder}/build.sh",
    "problemMatcher": [],
    "group": {
        "kind": "build",
        "isDefault": true
    }
}
```

Больше примеров можно найти в репозитории.
TODO: ссылка на репозиторий

### Расширение для PostgreSQL

Раз мы говорим про VS Code, то стоит рассказать и о расширениях. Одно из
полезных - это `PostgreSQL Hacker Helper`.

Главная фича - окно просмотра переменных. Это тоже самое окно переменных, но
дополнительно показывает узлы согласно их реальным тегам. Мы уже видели пример -
когда отлаживали неправильно поведение планировщика. Кроме того, он показывает
элементы узлов-контейнеров: `List` (включая подтипы) и `Bitmapset`.

У него есть и другие фичи, например, вызов `pprint` для переменной узла.

При отладке сохраняет много времени.

## Итоги

Подытожим что сделали:

- Изучили общий план работы планировщика, основные этапы и функции
- Познакомлись с узлами: тэги, наследование, полезные функции и макросы
- Добавили оптимизацию в парсер и планировщик
- Запустили код под отладкой и исправили баг
