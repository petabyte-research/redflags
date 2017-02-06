--
--   Copyright 2014-2016 PetaByte Research Ltd.
--
--   Licensed under the Apache License, Version 2.0 (the "License");
--   you may not use this file except in compliance with the License.
--   You may obtain a copy of the License at
--
--       http://www.apache.org/licenses/LICENSE-2.0
--
--   Unless required by applicable law or agreed to in writing, software
--   distributed under the License is distributed on an "AS IS" BASIS,
--   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--   See the License for the specific language governing permissions and
--   limitations under the License.
--

-- NOTICES

drop table if exists rfwl_temp_dt;
create table rfwl_temp_dt as
select r.relationLeftId noticeId, r.relationRightId 'typeId', dt.name 'typeName'
from te_relationdescriptor r
inner join te_datatype dt on dt.id = r.relationRightId and r.additonalInfo = "documentType";
alter table rfwl_temp_dt change column `noticeId` `noticeId` varchar(200) not null, add primary key (`noticeId`);

drop table if exists rfwl_temp_co;
create table rfwl_temp_co as
select r.relationLeftId noticeId, r.relationRightId orgId, o.name orgName
from te_relationdescriptor r inner join te_organization o on o.id = r.relationRightId and r.additonalInfo = "contractingOrg";
alter table rfwl_temp_co change column `noticeId` `noticeId` varchar(200) not null, add primary key (`noticeId`);

drop table if exists rfwl_temp;
create table rfwl_temp as
	select
		n.id 'id',
		n.documentFamilyId 'documentFamilyId',
		n.tedUrl 'url',
		d.publicationDate 'date',
		t.typeId 'typeId',
		t.typeName 'type',
		c.orgId 'contractingOrgId',
		c.orgName 'contractingOrgName',
		o.contractTitle 'title',
		o.estimatedValue 'estimated',
		o.estimatedValueCurr 'estimatedCurr',
		o.totalFinalValue 'total',
		o.totalFinalValueCurr 'totalCurr',
		fcs.fc 'flagCount'
	from
		(select id, documentFamilyId, tedUrl from te_notice order by noticeYear desc, noticeNumber desc) n
		left join te_data d on n.id = d.id
		left join rfwl_temp_dt t on n.id = t.noticeId
		left join rfwl_temp_co c on n.id = c.noticeId
		left join te_objofthecontract o on o.id = CONCAT(n.id, '-O-1')
		left join (
			select noticeId, count(*) fc from te_flag group by noticeId
		) fcs on n.id = fcs.noticeId
;
alter table rfwl_temp add primary key (id), add index (flagCount);
drop table if exists rfwl_notices;
rename table rfwl_temp to rfwl_notices;
drop table if exists rfwl_temp_dt;
drop table if exists rfwl_temp_co;

-- ORGANIZATIONS

drop table if exists rfwl_temp;
create table rfwl_temp as
	select
		o.id 'id',
		name 'name',
		_type 'type',
		c.calls 'calls',
		w.wins 'wins'
	from
		(select * from te_organization order by name) o
		left join (
			select contractingOrgId 'id', count(*) 'calls'
			from rfwl_notices
			where typeId = "TD-3"
			group by contractingOrgId
			) c on o.id = c.id
		left join (
			select relationRightId 'orgId', count(distinct substring(relationLeftId, 1, position('-A-' in relationLeftId)-1)) 'wins'
			from te_relationdescriptor
			where additonalInfo = "winnerOrg"
			group by relationRightId
			) w on o.id = w.orgId
; -- 6.5 sec
alter table rfwl_temp add primary key (id);
drop table if exists rfwl_organizations;
rename table rfwl_temp to rfwl_organizations;

-- CPVS

drop table if exists rfwl_temp;
create table rfwl_temp as
	select
		relationLeftId 'noticeId',
		group_concat(relationRightId separator '|') 'cpvs'
	from te_relationdescriptor
	where _type = "DATA_TO_CPV"
	group by relationLeftId
; -- 1.2 sec
alter table rfwl_temp change column `noticeId` `noticeId` VARCHAR(200) NOT NULL , add primary key (`noticeId`);
drop table if exists rfwl_cpvs;
rename table rfwl_temp to rfwl_cpvs;

-- WINNERS

drop table if exists rfwl_temp;
create table rfwl_temp as
	select
		nid 'noticeId',
		oid 'winnerOrgId',
		o.name 'winnerOrgName'
	from
		(select substring(relationLeftId, 1, position('-A-' in relationLeftId)-1) nid, relationRightId oid
		from te_relationdescriptor
		where additonalInfo = "winnerOrg") r
		inner join te_organization o on o.id = r.oid
; -- 0.6 sec
alter table rfwl_temp
	change column `noticeId` `noticeId` varchar(20) not null,
	change column `winnerOrgId` `winnerOrgId` varchar(200) not null,
	change column `winnerOrgName` `winnerOrgName` longtext not null,
	add index `id` (`noticeId` asc);
drop table if exists rfwl_winners;
rename table rfwl_temp to rfwl_winners;

-- BAR PLOT

drop table if exists rfwl_temp;
create table if not exists rfwl_temp as
	select year(n.date) y, r.relationRightId c, sum(n.total) / 1000000000 v
	from
		rfwl_notices n
		inner join te_relationdescriptor r on r.relationLeftId = n.id
	where
		typeId="TD-7" and r.additonalInfo = "contractType"
	group by year(n.date), r.relationRightId;
drop table if exists rfwl_barplot;
rename table rfwl_temp to rfwl_barplot;

-- USERS CLEANING

-- delete from rfwl_users where active = 0 and remember_token_expires_at < now()