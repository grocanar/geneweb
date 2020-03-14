set @id = 460;

with recursive ancestors as (
 select 1 as "gen", cast("1" as decimal(20)) as "sosa", g_id, p_id
 from person_group
 where p_id = @id and role = 'Child'
union
 select a.gen+1, a.sosa*2+if(persons.sex = 'F', 1, 0), c.g_id, p.p_id
 from person_group p
 inner join persons using(p_id)
 inner join ancestors a on p.g_id = a.g_id and p.role = 'Parent'
 left join person_group c on p.p_id = c.p_id and p.role = 'Parent' and c.role = 'Child'
 -- where a.gen < 5
)

-- Version complète
-- select anc.gen, anc.sosa, n.givn, n.surn
-- from ancestors anc
-- inner join person_name pn on anc.p_id = pn.p_id and n_type = 'Main'
-- inner join names n using(n_id)
-- ;

select anc2.gen, anc2.sosa, n.givn, n.surn
from
 (
  select min(anc.gen) as "gen", min(anc.sosa) as "sosa", p_id
  from ancestors anc
  group by p_id
  order by 1, 2
 ) as anc2
inner join person_name pn on anc2.p_id = pn.p_id and n_type = 'Main'
inner join names n using(n_id)
;
