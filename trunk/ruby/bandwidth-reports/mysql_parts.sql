DELIMITER //

CREATE FUNCTION `total_from_delta`(itemid int, startdate date, days int) 
RETURNS bigint(20)
BEGIN
	declare starttime,endtime, startt, endt int;
	declare nearendtime int;
	declare calctime int;
	declare total bigint default 0;
	declare prevtime,cur_time, val int;

	declare done int default 0;
	declare cursor1 cursor for select h.clock,h.value from history h where
	h.clock>=starttime and h.clock<=endtime and h.itemid=itemid;

	set calctime = unix_timestamp(timestampadd(day,days,startdate));
	if days>0 then
		select h.clock into starttime from history h where
			h.itemid=itemid and h.clock>=unix_timestamp(startdate) limit 1;
		select h.clock into endtime from history h where
			h.itemid=itemid and h.clock>=calctime limit 1;
		select h.clock into nearendtime from history h where
			h.itemid=itemid and h.clock>=starttime and h.clock<=calctime
			order by clock desc limit 1;
			set endtime = ifnull(endtime,nearendtime);
	else
		select h.clock into starttime from history h where
			h.itemid=itemid and h.clock>=calctime limit 1;
		select h.clock into endtime from history h where
			h.itemid=itemid and h.clock>=(unix_timestamp(startdate)) limit 1;
	select h.clock into nearendtime from history h where
			itemid=itemid and h.clock>=starttime and h.clock<=unix_timestamp(startdate)
			order by clock desc limit 1;
	end if;

	begin
		declare continue handler for sqlstate '02000' set done = 1;
		open cursor1;
		fetch cursor1 into prevtime, val;
		repeat
		fetch cursor1 into cur_time,val;
		if not done then
			set total = total + (val * (cur_time - prevtime));
		end if;
		set prevtime=cur_time;
		until done end repeat;
		close cursor1;
	end;

	return total;
END//

DELIMITER ;

CREATE VIEW `net_ifgroups` AS 
 (select `items`.`itemid` AS `itemid`,`hosts`.`host` AS `host`,
  concat(_latin1'if_',substr(`items`.`description`,11)) AS `interface`,
  _utf8'inbound' AS `type` from (`items` join `hosts`) 
 where 
  ((`items`.`hostid` = `hosts`.`hostid`) and (`items`.`type` = 4) 
   and (`hosts`.`status` = 0) and (`items`.`status` = 0) 
   and (`items`.`description` like _latin1'ifinoctets%'))) 
union 
 (select `items`.`itemid` AS `itemid`,`hosts`.`host` AS `host`,
  concat(_latin1'if_',substr(`items`.`description`,12)) AS `interface`
  ,_utf8'outbound' AS `type` from (`items` join `hosts`) 
 where 
  ((`items`.`hostid` = `hosts`.`hostid`) and (`items`.`type` = 4) 
   and (`hosts`.`status` = 0) and (`items`.`status` = 0) 
   and (`items`.`description` like _latin1'ifoutoctets%'))) 
order by `itemid`
