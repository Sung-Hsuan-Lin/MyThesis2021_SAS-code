/*-------------------------------create library-------------------------------*/
libname new "F:\portfolio\new"; /*store the new data*/
libname raw "F:\portfolio\raw"; /*copy raw data to this folder*/
libname smoke "F:\Smoking cessation"; /*original dataset*/


/**********************************main program**********************************/
/*------------------------------------------------------------------------------*/
/*part 0: import and back up the data                                           */
/*------------------------------------------------------------------------------*/
/*part1: merge data, select the variables                                       */
/*------------------------------------------------------------------------------*/
/*part2: modify variables                                                       */
/*  part2-1: modify error id                                                    */
/*  part2-2: modify error birthday                                              */
/*  part2-3: modify smokedaynum and smokescore                                  */
/*  part2-4: modify the format of the variables                                 */
/*------------------------------------------------------------------------------*/
/*part3: screening sample                                                       */
/*------------------------------------------------------------------------------*/
/*part4: create variables which in reserch                                      */
/*------------------------------------------------------------------------------*/
/*part5: statistical analysis                                                   */
/*------------------------------------------------------------------------------*/
/********************************************************************************/


/*part 0: import and back up the data-------------------------------------------*/
%macro impdata(data, name)/des="import data";
   proc import
        datafile="F:\Smoking cessation\&data"
        out=raw.&name
        dbms=csv 
        replace;
        getnames=yes;
        guessingrows=1000 ;
    run;
%mend impdata;
%impdata(dbo_MhbtQsData.txt, QsData); /*3870723 observations, 44 variables*/
%impdata(dbo_MhbtQsCure.txt, QsCure); /*3162273 observations, 9 variables*/
%impdata(dbo_GenDrugBasic.txt, GDB); /*60 observations and 10 variables*/

data raw.L7a; /*41000 observations, 36 variables*/
  set smoke.Long_7a_modified;
run;

/*part1: merge data, select the variables---------------------------------------*/
proc sql;
  create table new.merge_data as  /*4752290 rows and 21 columns*/
  select distinct a.hospid, a.id, a.birthday, a.funcdate, a.firsttreatdate, a.curestage, 
                  a.cure_type, a.smokedaynum, a.smokescore, a.cureweek, 
                  b.cureitem, c.DrugIngredient,  
                  d.f1, d.c1, d.b3, d.nct1, d.nct2, d.nct3, 
                  d.nqd1 format yymmdd10., 
                  d.nqd2 format yymmdd10., 
                  d.nqd3 format yymmdd10.
  from raw.qsdata as a 
  left join raw.qscure as b 
  on (a.id=b.id) and (a.hospid=b.hospid) and (a.funcdate=b.funcdate)
  left join raw.gdb as c
  on (b.cureitem=c.drugno)
  left join raw.l7a as d
  on (a.id=d.id) and (substr(a.firsttreatdate,1,6)=d.firstmonth) and (a.hospid=d.hospid);
quit;

/*part2: modify variables--------------------------------------------------*/
/*part2-1: modify error id-------------------------------------------------*/
%include "F:\portfolio\code\subroutine_modify id.sas";

/*part2-2: modify error birthday-------------------------------------------*/
%include "F:\portfolio\code\subroutine_modify bd.sas";

/*part2-3: modify smokedaynum and smokescore-------------------------------*/
/*??????di, birthday, funcdate??????smokedaynum???smokescore?????? (????????????????????????)????????????????????????????????????????????????*/
proc sql;
  create table new.adh_data as /* 4752290 rows and 24 columns*/
  select *, max(SmokeDayNum) as newsdn, 
         max(input(SmokeScore, best12.)) as newss
  from new.bd_data
  group by id, birthday, funcdate;
quit;

/*part2-4: modify the format of the variables------------------------------*/
/*1. ?????????id*/
/*2. birthday???funcdate???firsttreatdate??????????????????*/
proc sql;
  create table new.format_data as /*3938019 rows and 21 columns*/
  select distinct hospid, id, f1, c1, b3 format best12., nct1, nct2, nct3, nqd1, nqd2, nqd3,
         cats(id,birthday) as newid,
	 input(birthday, yymmdd10.) as bd format yymmdd10.,
	 input(funcdate, yymmdd10.) as funcdate format yymmdd10.,
	 input(firsttreatdate, yymmdd10.) as firstdate format yymmdd10.,
	 curestage, cure_type, newsdn, newss, cureweek, 
         case when substr(DrugIngredient,1,1)="V" then "V"
	      when substr(DrugIngredient,1,1)="B" then "B"
	      when substr(DrugIngredient,1,1)="N" then "N"
	      else " " 
	 end as drug
   from new.adh_data;
quit;

/*part3: screening sample-------------------------------------------------*/
/*1. ?????????*/
/*2. ??????????????????????????????*/
/*3. ??????????????????>=18??????*/
/*4. ???????????????6??????follow up ??????*/
proc sql; 
  create table new.screen_data as/*6574 rows and 22 columns*/
  select distinct *, floor(yrdif(bd, min(firstdate), 'age')) as firstage
  from new.format_data
  where (Cure_Type="1") and (curestage="1")
  group by newid
  having (firstdate=min(firstdate)) and
         (mdy(2,1,2015)<=min(firstdate)<=mdy(1,31,2016) or
          mdy(6,12,2017)<=min(firstdate)<=mdy(6,11,2018)) and
         (firstage>=18) and
         ((nct1=0) or (nct2=0) or (nct3=0));
quit;

/*part4: create variables which in reserch--------------------------------*/
proc sql; /*???????????????: adh, usedrug, addweek*/
  create table adh as /*3336 rows and 2 columns*/
  select newid, sum(cureweek) as adh
  from (select distinct newid, funcdate, cureweek from new.screen_data)
  group by newid;

  create table usedrug as /*3336 rows and 2 columns*/
  select distinct newid, case when (count(drug)=1) and (drug="V") then 0 
	                      when (count(drug)=1) and (drug="B") then 1
                              when (count(drug)=1) and (drug="N") then 2 
			      when (count(drug)>1) then 3
                              else . 
                         end as usedrug 
   from (select distinct newid, drug from new.screen_data where drug not in (" "))/*????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????*/
   group by newid;

   create table addweek as /*444 rows and 2 columns*/
   select newid, sum(cureweek) as addweek
   from (select distinct a.newid, a.funcdate, a.cureweek, b.firstdate
	 from new.format_data as a left join new.screen_data as b
	 on a.newid=b.newid
	 where (a.newid in (select newid from new.screen_data)) and (a.cure_type="1")
	 having b.firstdate+90<a.funcdate<b.firstdate+180)
    group by newid;

    create table adh_usedrug as /*3336 rows and 3 columns*/
    select a.*, b.usedrug
    from adh as a left join usedrug as b
    on a.newid=b.newid;

    create table var as /*3336 rows and 4 columns*/
    select distinct a.*, b.addweek
    from adh_usedrug as a left join addweek as b
    on a.newid=b.newid;
quit;

proc sql; /*??????????????????????????????*/
  create table new.analysis as /*3324 rows and 16 columns*/
  select distinct a.id, a.newid, a.firstage, a.newss as firstftnd, a.newsdn as firstsdn, b.adh, b.usedrug,
                  case when mdy(2,1,2015)<=a.firstdate<=mdy(1,31,2016) then 0
	               when mdy(6,12,2017)<=a.firstdate<=mdy(6,11,2018) then 1
	               else . 
	          end as tax2,
	          case when 18<=a.firstage<=29 then 0
                       when 30<=a.firstage<=49 then 1
		       when 50<=a.firstage<=64 then 2
		       when a.firstage>=65 then 3
		       else .
		   end as casefirstage,
	           case when substr(a.id,2,1)="1" then 0
			when substr(a.id,2,1)="2" then 1
			else .
		   end as sex,
	           case when a.f1 in (1, 2) then 0
			when a.f1=3 then 1
			when a.f1=4 then 2
			when a.f1 in (5, 6) then 3
			else .
		   end as edu,
		   case when a.c1 in (991, 0) then 0
			when a.c1 in (1-10) then 1
			else . 
		   end as famsmoker,
		   case when a.newss in (0, 1, 2, 3) then 0
			when a.newss in (4, 5, 6) then 1
			when a.newss in (7, 8, 9, 10) then 2
			else .
		   end as casefirstftnd,
		   case when a.newsdn<=10 then 0
			when 11<=a.newsdn<=20 then 1
			when 21<=a.newsdn<=30 then 2
			when a.newsdn>=31 then 3
			else .
		   end as casefirstsdn,
		   case when a.b3 in (1, 2, 3) then 0
			when a.b3 in (4, 5) then 1
			else .
		   end as quit,
		   case when b.addweek>0 then b.addweek
			when b.addweek=. then 0
			else .
		   end as addweek
  from new.screen_data as a left join var as b
  on a.newid=b.newid
  group by a.newid
  having (funcdate=firstdate) and quit^=.;/*???12??????quit??????????????????????????????????????????*/
quit;

/*part5: statistical analysis------------------------------------------------*/
/*???????????????*/
proc ttest data=new.analysis;
  class tax2;
  var firstage adh addweek;
run;

proc freq data=new.analysis;
  table tax2*(sex casefirstage edu casefirstsdn casefirstftnd famsmoker usedrug)/chisq;
run;

/*???????????????*/
proc genmod data=new.analysis;
  class tax2 (ref="0")
        sex (ref="0")
	casefirstage (ref="0")
	edu (ref="0")
	casefirstsdn (ref="0")
	casefirstftnd (ref="0")
	famsmoker (ref="0")
	usedrug (ref="0");
  where edu^=. and famsmoker^=.;
  model adh=tax2 sex casefirstage edu casefirstsdn casefirstftnd famsmoker usedrug/dist=poisson link=log dscale;
run;
