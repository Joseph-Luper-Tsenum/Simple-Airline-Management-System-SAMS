-- CS4400: Introduction to Database Systems: Tuesday, September 12, 2023
-- Simple Airline Management System Course Project Mechanics [GROUP 65] (v0)
-- Views, Functions & Stored Procedures

/* This is a standard preamble for most of our scripts.  The intent is to establish
a consistent environment for the database behavior. */
set global transaction isolation level serializable;
set global SQL_MODE = 'ANSI,TRADITIONAL';
set names utf8mb4;
set SQL_SAFE_UPDATES = 0;

set @thisDatabase = 'flight_tracking';
use flight_tracking;
-- -----------------------------------------------------------------------------
-- stored procedures and views
-- -----------------------------------------------------------------------------
/* Standard Procedure: If one or more of the necessary conditions for a procedure to
be executed is false, then simply have the procedure halt execution without changing
the database state. Do NOT display any error messages, etc. */

-- [_] supporting functions, views and stored procedures
-- -----------------------------------------------------------------------------
/* Helpful library capabilities to simplify the implementation of the required
views and procedures. */
-- -----------------------------------------------------------------------------
drop function if exists leg_time;
delimiter //
create function leg_time (ip_distance integer, ip_speed integer)
	returns time reads sql data
begin
	declare total_time decimal(10,2);
    declare hours, minutes integer default 0;
    set total_time = ip_distance / ip_speed;
    set hours = truncate(total_time, 0);
    set minutes = truncate((total_time - hours) * 60, 0);
    return maketime(hours, minutes, 0);
end //
delimiter ;


#New supporting procedures

drop function if exists flight_max_sequence
delimiter //
create function flight_max_sequence (ip_flightID varchar(50))
#Args: flightID
#Returns: max_sequence (integer) - final sequence index number in a route given a flightID ip_flightID
	returns integer reads sql data
begin
	declare max_sequence integer;
    select max(sequence) into max_sequence from route_path r join flight f on r.routeID = f.routeID where f.flightID = ip_flightID;
	return max_sequence;
end //
delimiter;

drop function if exists flight_speed
delimiter //
create function flight_speed (ip_flightID varchar(50))
#Args: flightID
#Returns: flight_speed (integer) - Speed of the flight with the flightID ip_flightID
	returns integer reads sql data
begin
	declare flight_speed integer;
    select speed into flight_speed from airplane join flight on (airlineID, tail_num) = (support_airline, support_tail) where flightID = ip_flightID;
	return flight_speed;
end //
delimiter ;

drop function if exists flight_airplane_type
delimiter //
create function flight_airplane_type (ip_flightID varchar(50))
#Args: flightID
#Returns: plane_type (varchar(100)) - Type of a flight's supporting airplane.
	returns varchar(100) reads sql data
begin
	declare flight_type varchar(100);
	select plane_type into flight_type from airplane 
    where (airlineID, tail_num) = (select support_airline, support_tail from flight where flightID = ip_flightID);
	return flight_type;
end //
delimiter ;

drop function if exists flight_on_ground_nextlegID;
delimiter //
create function flight_on_ground_nextlegID (ip_flightID varchar(50))
#Args: flightID
#Returns: legID (varchar(50)) - the legID of a sequence in a flight's route.
	returns varchar(50) reads sql data
begin
    declare ip_sequence integer;
	declare sequence_legID varchar(50);
    select progress + 1 into ip_sequence from flight where flightID = ip_flightID;
    select legID into sequence_legID from route_path
	where routeID = (select routeID from flight where flightID = ip_flightID)
	and sequence = ip_sequence;
    return sequence_legID;
 end //
delimiter ;

drop function if exists flight_next_leg_distance;
delimiter //
create function flight_next_leg_distance (ip_flightID varchar(50))
#Args: flightID
#Returns: leg_distance (integer) - distance from start to end of leg given its flightID.
	returns integer reads sql data
begin
	declare leg_distance integer;
    select distance into leg_distance from leg
	where legID = flight_on_ground_nextlegID(ip_flightID);
    return leg_distance;
 end //
delimiter ;

drop function if exists flight_next_time;
delimiter //
create function flight_next_time (ip_flightID varchar(50), ip_next_time TIME, ip_status varchar(50))
#Args: flightID,
#next_time, 
#status: 'landing' or 'takeoff' or 'insufficent_pilots_takeoff'
#Returns: next_time (TIME) - next_time of a flight given the status
	returns TIME reads sql data
begin
	declare next_leg_time TIME;
    declare next_legID varchar(50);
    if ip_status = 'landing'
		then return cast(date_add(cast(ip_next_time as datetime), interval 1 hour) as time); 
        end if;
	if ip_status = 'takeoff'
		then 
        set next_leg_time = leg_time(flight_next_leg_distance(ip_flightID), flight_speed(ip_flightID));
        return cast(date_add(cast(ip_next_time as datetime), interval next_leg_time hour_second) as time);
        end if;
	if ip_status = 'insufficient_pilots_takeoff'
		then
        set next_leg_time = leg_time(flight_next_leg_distance(ip_flightID), flight_speed(ip_flightID));
		return cast(date_add(date_add(cast(ip_next_time as datetime), interval next_leg_time hour_second), interval 30 minute) as time); #Delay
        end if;
 end //
delimiter ;

drop function if exists route_max_sequence
delimiter //
create function route_max_sequence (ip_routeID varchar(50))
#Args: routeID
#Returns: max_sequence (integer) - final sequence index number in a route given its routeID ip_routeID.
	returns integer reads sql data
begin
	declare max_sequence integer;
	select max(sequence) into max_sequence from route_path where routeID = ip_routeID;
	return max_sequence;
end //
delimiter;
-- [1] add_airplane()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new airplane.  A new airplane must be sponsored
by an existing airline, and must have a unique tail number for that airline.
username.  An airplane must also have a non-zero seat capacity and speed. An airplane
might also have other factors depending on it's type, like skids or some number
of engines.  Finally, an airplane must have a new and database-wide unique location
since it will be used to carry passengers. */
-- -----------------------------------------------------------------------------
delimiter //
create procedure add_airplane (in ip_airlineID varchar(50), in ip_tail_num varchar(50),
	in ip_seat_capacity integer, in ip_speed integer, in ip_locationID varchar(50),
    in ip_plane_type varchar(100), in ip_skids boolean, in ip_propellers integer,
    in ip_jet_engines integer)
sp_main: begin

if ip_airlineID not in (select airlineID from airline) # If airline doesn't exist, leave.
	then leave sp_main; end if;

if (ip_airlineID, ip_tail_num) in (select airlineID, tail_num from airplane) # If airplane already exists, leave.
	then leave sp_main; end if;

if ip_locationID in (select locationID from location) # If locationID already exists, leave.
	then leave sp_main; end if;
        
if ip_seat_capacity <= 0 or ip_speed <= 0 # If seat_capacity or speed are non-positive, leave.
	then leave sp_main; end if;
        
if ip_plane_type = 'prop' and (ip_skids is null or ip_propellers is null or ip_propellers <= 0 or ip_jet_engines is not null) # Leave if prop has jet engines or non-positive/null propellers/skids
    then leave sp_main; end if;
        
if ip_plane_type = 'jet' and (ip_skids is not null or ip_propellers is not null or ip_jet_engines is null or ip_jet_engines <= 0) # Leave if jet has skids or propellers or non-positive/null engines
    then leave sp_main; end if;


#Insert after conditions have been checked.

insert into location values (ip_locationID);
insert into airplane values (ip_airlineID, ip_tail_num, ip_seat_capacity, ip_speed, ip_locationID, ip_plane_type, ip_skids, ip_propellers, ip_jet_engines);
end //
delimiter ;

-- [2] add_airport()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new airport.  A new airport must have a unique
identifier along with a new and database-wide unique location if it will be used
to support airplane takeoffs and landings.  An airport may have a longer, more
descriptive name.  An airport must also have a city, state, and country designation. */
-- -----------------------------------------------------------------------------
drop procedure if exists add_airport;
delimiter //
create procedure add_airport (in ip_airportID char(3), in ip_airport_name varchar(200),
    in ip_city varchar(100), in ip_state varchar(100), in ip_country char(3), in ip_locationID varchar(50))
sp_main: begin

if ip_airportID in (select airportID from airport) # Leave if airportID exists
	then leave sp_main; end if;

if ip_locationID is not null and ip_locationID in (select locationID from location) # Leave if locationID exists.
        then leave sp_main; end if;

if ip_city is null or ip_state is null or ip_country is null # Leave if city,state, country are null
        then leave sp_main; end if;


#Insert after conditions have been checked.
if ip_locationID is not null
	then insert into location values (ip_locationID); end if;
insert into airport values (ip_airportID, ip_airport_name, ip_city, ip_state, ip_country, ip_locationID);
end //
delimiter ;

-- [3] add_person()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new person.  A new person must reference a unique
identifier along with a database-wide unique location used to determine where the
person is currently located: either at an airport, or on an airplane, at any given
time.  A person must have a first name, and might also have a last name.

A person can hold a pilot role or a passenger role (exclusively).  As a pilot,
a person must have a tax identifier to receive pay, and an experience level.  As a
passenger, a person will have some amount of frequent flyer miles, along with a
certain amount of funds needed to purchase tickets for flights. */
-- -----------------------------------------------------------------------------


drop procedure if exists add_person;
delimiter //
create procedure add_person (in ip_personID varchar(50), in ip_first_name varchar(100),
    in ip_last_name varchar(100), in ip_locationID varchar(50), in ip_taxID varchar(50),
    in ip_experience integer, in ip_miles integer, in ip_funds integer)
sp_main: begin

if ip_personID in (select personID from person) # Leave if person exists.
	then leave sp_main; end if;
    
if ip_first_name is null or ip_locationID is null # Leave if first name or locationID are null.
	then leave sp_main; end if;

if (ip_taxID is not null or ip_experience is not null) and (ip_miles is not null or ip_funds is not null) # Leave if person has both pilot and passenger attributes.
	then leave sp_main; end if;

if ip_locationID not in (select locationID from location) # Leave if location doesn't exist
	then leave sp_main; end if;

if ip_taxID is not null and ip_experience is not null # if person is a pilot
	then
    insert into person values (ip_personID, ip_first_name, ip_last_name, ip_locationID);
    insert into pilot values (ip_personID, ip_taxID, ip_experience, null);
	end if;

if ip_miles is not null and ip_funds is not null #If person is a passenger
	then 
	insert into person values (ip_personID, ip_first_name, ip_last_name, ip_locationID);
    insert into passenger values (ip_personID, ip_miles, ip_funds);
	end if;
end //
delimiter ;

-- [4] grant_or_revoke_pilot_license()
-- -----------------------------------------------------------------------------
/* This stored procedure inverts the status of a pilot license.  If the license
doesn't exist, it must be created; and, if it laready exists, then it must be removed. */
-- -----------------------------------------------------------------------------
drop procedure if exists grant_or_revoke_pilot_license;
delimiter //
create procedure grant_or_revoke_pilot_license (in ip_personID varchar(50), in ip_license varchar(100))
sp_main: begin

if ip_personID not in (select personID from pilot) # Leave if pilot does not exist
	then leave sp_main; end if;
if (ip_personID, ip_license) not in (select personID, license from pilot_licenses) # Insert pilot-license pair if it doesn't exist
	then insert into pilot_licenses VALUES (ip_personID, ip_license);
    leave sp_main; end if;
if (ip_personID, ip_license) in (select personID, license from pilot_licenses) # Remove pilot-license pair if it exists
	then delete from pilot_licenses where personID = ip_personID and license = ip_license;
    leave sp_main; end if;
end //
delimiter ;

-- [5] offer_flight()
-- -----------------------------------------------------------------------------
/* This stored procedure creates a new flight.  The flight can be defined before
an airplane has been assigned for support, but it must have a valid route.  And
the airplane, if designated, must not be in use by another flight.  The flight
can be started at any valid location along the route except for the final stop,
and it will begin on the ground.  You must also include when the flight will
takeoff along with its cost. */
-- -----------------------------------------------------------------------------
drop procedure if exists offer_flight;
delimiter //
create procedure offer_flight (in ip_flightID varchar(50), in ip_routeID varchar(50),
    in ip_support_airline varchar(50), in ip_support_tail varchar(50), in ip_progress integer,
    in ip_next_time time, in ip_cost integer)
sp_main: begin

if ip_flightID in (select flightID from flight) # Leave if flight exists
	then leave sp_main; end if;

if (ip_support_airline, ip_support_tail) in (select support_airline, support_tail from flight) # Leave if airplane is assigned to another flight
	then leave sp_main; end if;
    
if ip_routeID not in (select routeID from route) # Leave if route does not exist
	then leave sp_main; end if;
    
if ip_progress =  (select max(sequence) from route_path where routeID = ip_routeID) # Leave if at the final stop
	then leave sp_main; end if;
    
insert into flight VALUES (ip_flightID, ip_routeID, ip_support_airline, ip_support_tail, ip_progress, 'on_ground', ip_next_time, ip_cost);
end //
delimiter ;

-- [6] flight_landing()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a flight landing at the next airport
along it's route.  The time for the flight should be moved one hour into the future
to allow for the flight to be checked, refueled, restocked, etc. for the next leg
of travel.  Also, the pilots of the flight should receive increased experience, and
the passengers should have their frequent flyer miles updated. */
-- -----------------------------------------------------------------------------
#TODO:
# - Do we need to check if flight exists?
# - Do we need to check if flight has passengers and pilots?
# - Do we need to check if progress is valid?
# - Find cleaner way to increment time without setting time over 24:00:00.
# - Should we update progress?
# - Do we need to check if progress is equal to the final stop?
# - Should we set status to on_ground?
# - Is the speed miles/hour?
	# - So passenger miles += flight_speed?
drop procedure if exists flight_landing;
delimiter //
create procedure flight_landing (in ip_flightID varchar(50))
sp_main: begin

if ip_flightID not in (select flightID from flight)
	then leave sp_main; end if;
if (select airplane_status from flight where flightID = ip_flightID) = 'on_ground'
	then leave sp_main; end if;
#Maybe we should check/update the progress 
#if (select progress from flight where flightID = ip_flightID) = flight_max_sequence(ip_flightID)
#	then leave sp_main; end if;

update flight 
set next_time = flight_next_time(ip_flightID, next_time, 'landing'),
airplane_status = 'on_ground' where flightID=ip_flightID;
#, progress = progress + 1 where flightID=ip_flightID;

update pilot
set experience = experience + 1 where commanding_flight = ip_flightID;




update passenger p 
	join person as pe on p.personID=pe.personID 
	join airplane as a on a.locationID=pe.locationID
	join flight as f on (f.support_airline, f.support_tail) = (a.airlineID, a.tail_num)
    join route_path as rp on rp.routeID = f.routeID and rp.sequence = f.progress
    join leg as l on l.legID = rp.legID
set p.miles = p.miles + l.distance where ip_flightID = f.flightID;
end //
delimiter ;

-- [7] flight_takeoff()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for a flight taking off from its current
airport towards the next airport along it's route.  The time for the next leg of
the flight must be calculated based on the distance and the speed of the airplane.
And we must also ensure that propeller driven planes have at least one pilot
assigned, while jets must have a minimum of two pilots. If the flight cannot take
off because of a pilot shortage, then the flight must be delayed for 30 minutes. */
-- -----------------------------------------------------------------------------
#TODO:
# - Do we need to check if flight exists?
# - Do we need to check if flight has passengers?
# - Do we need to check if progress is valid?
# - Find cleaner way to increment time without setting time over 24:00:00.
# - Should we update progress?
# - Do we need to check if progress is equal to the final stop?
# - Should we set status to in_flight?

drop procedure if exists flight_takeoff;
delimiter //
create procedure flight_takeoff (in ip_flightID varchar(50))
sp_main: begin

if ip_flightID not in (select flightID from flight)
	then leave sp_main; end if;
if (select airplane_status from flight where flightID = ip_flightID) = 'in_flight'
	then leave sp_main; end if;
#Maybe we should check/update the progress
if (select progress from flight where flightID = ip_flightID) = flight_max_sequence(ip_flightID)
	then leave sp_main; end if;

if (flight_airplane_type(ip_flightID) = 'prop' 
and (select count(*) from pilot where commanding_flight = ip_flightID)  < 1)
or
(flight_airplane_type(ip_flightID) = 'jet' 
and (select count(*) from pilot where commanding_flight = ip_flightID)  < 2)
	then 
	update flight 
    set next_time = flight_next_time(ip_flightID, next_time, 'insufficient_pilots_takeoff'), 
		airplane_status = 'in_flight', 
		progress = progress + 1 
    where flightID = ip_flightID;
    leave sp_main; end if;
update flight set next_time = flight_next_time(ip_flightID, next_time, 'takeoff'), airplane_status = 'in_flight', progress = progress + 1 where flightID=ip_flightID;
end //
delimiter ;

-- [8] passengers_board()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for passengers getting on a flight at
its current airport.  The passengers must be at the same airport as the flight,
and the flight must be heading towards that passenger's desired destination.
Also, each passenger must have enough funds to cover the flight.  Finally, there
must be enough seats to accommodate all boarding passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists passengers_board;
delimiter //
create procedure passengers_board (in ip_flightID varchar(50))
sp_main: begin

if (select airplane_status from flight where flightID = ip_flightID) = 'in_flight' #leave if flight is in_flight (you can't let a passenger embark a flying plane)
	then leave sp_main; end if;
if (select progress from flight where flightID = ip_flightID) = flight_max_sequence(ip_flightID) #leave if flight is at the final stop
	then leave sp_main; end if;

#monster join to check if flight has enough seats
if (select count(*) from passenger p where p.personID in (select p.personID from passenger join person pe on p.personID = pe.personID 
join passenger_vacations pass_v on pe.personID=pass_v.personID
join airport a on pe.locationID=a.locationID
join leg l on a.airportID = l.departure 
join route_path r on r.legID = l.legID
join flight f on (f.routeID, f.progress+1) = (r.routeID, r.sequence)
join airplane plane on (plane.airlineID, plane.tail_num) = (f.support_airline, f.support_tail)
where pass_v.sequence = 1 
and pass_v.airportID = l.arrival 
and p.funds >= f.cost 
and f.flightID=ip_flightID))
 >
 (select seat_capacity from airplane join flight on (airplane.airlineID, airplane.tail_num) = (flight.support_airline, flight.support_tail) where flight.flightID=ip_flightID)
	then leave sp_main; end if;
    
update passenger p
join person pe on p.personID=pe.personID 
join passenger_vacations pass_v on p.personID=pass_v.personID
join airport a on pe.locationID=a.locationID
join leg l on a.airportID = l.departure 
join route_path r on r.legID = l.legID
join flight f on (f.routeID, f.progress+1) = (r.routeID, r.sequence) #f.progress+1?
join airplane plane on (plane.airlineID, plane.tail_num) = (f.support_airline, f.support_tail)
set pe.locationID = plane.locationID, p.funds = p.funds - f.cost
where pass_v.sequence = 1 and pass_v.airportID = l.arrival and p.funds >= f.cost and f.flightID=ip_flightID;

end //
delimiter ;

-- [9] passengers_disembark()
-- -----------------------------------------------------------------------------
/* This stored procedure updates the state for passengers getting off of a flight
at its current airport.  The passengers must be on that flight, and the flight must
be located at the destination airport as referenced by the ticket. */
-- -----------------------------------------------------------------------------
drop procedure if exists passengers_disembark;
delimiter //
create procedure passengers_disembark (in ip_flightID varchar(50))
sp_main: begin

if (select airplane_status from flight where flightID = ip_flightID) = 'in_flight'
	then leave sp_main; end if;

update passenger p
join person pe on p.personID=pe.personID 
join passenger_vacations pass_v on p.personID=pass_v.personID
join airplane a on pe.locationID = a.locationID
join flight f on (f.support_airline, f.support_tail) = (a.airlineID, a.tail_num)
join route_path rp on (f.routeID, f.progress) = (rp.routeID, rp.sequence)
join leg l on rp.legID = l.legID
join airport ap on l.arrival = ap.airportID
set pe.locationID = ap.locationID
where pass_v.sequence = 1 and (pass_v.airportID, 1) = (l.arrival, rp.sequence)  and f.flightID=ip_flightID;

delete pass_v from passenger p 
join passenger_vacations pass_v on p.personID=pass_v.personID 
join person pe on pe.personID = p.personID
join airport ap on ap.locationID = pe.locationID and pass_v.airportID = ap.airportID
where pass_v.sequence = 1;

update passenger_vacations
set sequence = sequence - 1 where personID not in (select personID from (select personID from passenger_vacations where sequence = 1) as temp);
end //

#does the following belong here or in passengers_embark? (or in any procedure?)
#delete from passenger_vacations where sequence = 0;
delimiter ;

-- [10] assign_pilot()
-- -----------------------------------------------------------------------------
/* This stored procedure assigns a pilot as part of the flight crew for a given
flight.  The pilot being assigned must have a license for that type of airplane,
and must be at the same location as the flight.  Also, a pilot can only support
one flight (i.e. one airplane) at a time.  The pilot must be assigned to the flight
and have their location updated for the appropriate airplane. */
-- -----------------------------------------------------------------------------
drop procedure if exists assign_pilot;
delimiter //
create procedure assign_pilot (in ip_flightID varchar(50), ip_personID varchar(50))
sp_main: begin

if (ip_personID not in (select personID from pilot))
		then leave sp_main; end if;



if ((select commanding_flight from pilot where personID = ip_personID) is not null)
		then leave sp_main; end if;
        

if (
	(select plane_type 
		from airplane 
		where tail_num in 
			(select support_tail from flight where flightID = ip_flightID))
	not in 
    (select license 
		from pilot_licenses 
		where personID = ip_personID))
then leave sp_main; end if;
    

if (
	(select locationID from person where personID = ip_personID)
	not in 
    (select locationID 
		from airport 
        where airportID in (
			select arrival from leg where legID in
				(select legID
					from route_path join flight 
					on flight.routeID = route_path.routeID and route_path.sequence = flight.progress
					where flightID = ip_flightID
				)
		)
	)
)
then leave sp_main; end if;

-- end final addition
update pilot
set commanding_flight = ip_flightID
where personID = ip_personID;

-- update loc
update person
set locationID = (select locationID from airplane where tail_num in (select support_tail from flight where flightID = ip_flightID))
where personID = ip_personID;


end //
delimiter ;

-- [11] recycle_crew()
-- -----------------------------------------------------------------------------
/* This stored procedure releases the assignments for a given flight crew.  The
flight must have ended, and all passengers must have disembarked. */
-- -----------------------------------------------------------------------------
drop procedure if exists recycle_crew;
delimiter //
create procedure recycle_crew (in ip_flightID varchar(50))
sp_main: begin

DECLARE result VARCHAR(50) DEFAULT 'test';
DECLARE maximum INT DEFAULT 0;


if ((select airplane_status from flight where flightID = ip_flightID) != 'on_ground')
then leave sp_main; end if;

SET maximum = (
select max(sequence) from flight natural join route_path
where flightID = ip_flightID);

if ((select progress from flight where flightID = ip_flightID) < maximum)
then leave sp_main; end if;

if (
	(select locationID 
		from airplane 
		where tail_num in 
			(select support_tail from flight where flightID = ip_flightID)
		and airlineID in 
			(select support_airline from flight where flightID = ip_flightID)
	)
	in (select locationID 
		from person 
		where personID in 
			(select personID from passenger)
		)
	)
then leave sp_main; end if;


SET result = 	(select locationID 
					from airport where airportID in (
						select arrival from leg where legID in
							(select legID
								from route_path join flight 
								on flight.routeID = route_path.routeID and route_path.sequence = flight.progress
								where flightID = ip_flightID
							)
					)
				);


update person
set locationID = result
where personID in 
(select personID from pilot where commanding_flight = ip_flightID);

update pilot
set commanding_flight = null
where commanding_flight = ip_flightID;


end //
delimiter ;

-- [12] retire_flight()
-- -----------------------------------------------------------------------------
/* This stored procedure removes a flight that has ended from the system.  The
flight must be on the ground, and either be at the start its route, or at the
end of its route.  And the flight must be empty - no pilots or passengers. */
-- -----------------------------------------------------------------------------
drop procedure if exists retire_flight;
delimiter //
create procedure retire_flight (in ip_flightID varchar(50))
sp_main: begin

DECLARE minimum INT DEFAULT 0;
DECLARE maximum INT DEFAULT 0;

SET minimum = (
select min(sequence) from flight natural join route_path
where flightID = ip_flightID);

SET maximum = (
select max(sequence) from flight natural join route_path
where flightID = ip_flightID);


if (select airplane_status from flight where flightID = ip_flightID) != 'on_ground'
then leave sp_main; end if;

if (select locationID from airplane where tail_num in 
		(select support_tail from flight where flightID = ip_flightID)) 
    in (select locationID from person)
then leave sp_main; end if;

if (select progress from flight where flightID = ip_flightID) > minimum and (select progress from flight where flightID = ip_flightID) < maximum
then leave sp_main; end if;

DELETE FROM flight WHERE flightID = ip_flightID;

end //
delimiter ;

-- [13] simulation_cycle()
-- -----------------------------------------------------------------------------
/* This stored procedure executes the next step in the simulation cycle.  The flight
with the smallest next time in chronological order must be identified and selected.
If multiple flights have the same time, then flights that are landing should be
preferred over flights that are taking off.  Similarly, flights with the lowest
identifier in alphabetical order should also be preferred.

If an airplane is in flight and waiting to land, then the flight should be allowed
to land, passengers allowed to disembark, and the time advanced by one hour until
the next takeoff to allow for preparations.

If an airplane is on the ground and waiting to takeoff, then the passengers should
be allowed to board, and the time should be advanced to represent when the airplane
will land at its next location based on the leg distance and airplane speed.

If an airplane is on the ground and has reached the end of its route, then the
flight crew should be recycled to allow rest, and the flight itself should be
retired from the system. */
-- -----------------------------------------------------------------------------
drop procedure if exists simulation_cycle;
delimiter //
create procedure simulation_cycle ()
sp_main: begin

DECLARE selected_flightID varchar(50);

select flightID into selected_flightID from flight where next_time = (select min(next_time) from flight) order by field(airplane_status, 'in_flight', 'on_ground'), (flightID) limit 1;

if (select airplane_status from flight where flightID = selected_flightID) = 'in_flight'
	then 
    call flight_landing(selected_flightID);
    call passengers_disembark(selected_flightID);
elseif (select airplane_status from flight where flightID = selected_flightID) = 'on_ground'
	then 
    if (select progress from flight where flightID = selected_flightID) = flight_max_sequence(ip_flightID)
		then 
        call recycle_crew(selected_flightID);
		call retire_flight(selected_flightID);
        
		leave sp_main; end if;
    call passengers_board(selected_flightID);
	call flight_takeoff(selected_flightID);
    
    end if;
end //
delimiter ;

-- [14] flights_in_the_air()
-- -----------------------------------------------------------------------------
/* This view describes where flights that are currently airborne are located. */
-- -----------------------------------------------------------------------------
create or replace view flights_in_the_air (departing_from, arriving_at, num_flights,
	flight_list, earliest_arrival, latest_arrival, airplane_list) as
select departure, arrival, count(*), group_concat(flightID), min(next_time), max(next_time), group_concat(locationID) 
from airplane join 
	(select departure, arrival, flightID, next_time, support_tail
	from leg join 
		(select flightID, legID, airplane_status, next_time, support_tail
		from flight join 
			route_path on (flight.routeID=route_path.routeID and flight.progress=route_path.sequence)) as info on info.legID=leg.legID
	where airplane_status = 'in_flight') as d on d.support_tail=airplane.tail_num
group by departure, arrival;

-- [15] flights_on_the_ground()
-- -----------------------------------------------------------------------------
/* This view describes where flights that are currently on the ground are located. */
-- -----------------------------------------------------------------------------
create or replace view flights_on_the_ground (departing_from, num_flights,
	flight_list, earliest_arrival, latest_arrival, airplane_list) as 
select arrival, count(*), group_concat(flightID), min(next_time), max(next_time), group_concat(locationID) 
from airplane join 
	((select arrival, flightID, next_time, support_tail
	from leg join 
		(select flightID, legID, airplane_status, next_time, support_tail
		from flight join 
			route_path on flight.routeID=route_path.routeID and (flight.progress=route_path.sequence)
		where airplane_status = 'on_ground'
		) as info on info.legID=leg.legID
	union
	select departure as 'arrival', flightID, next_time, support_tail
	from leg join 
		(select flightID, legID, airplane_status, next_time, support_tail
		from flight join 
			route_path on flight.routeID=route_path.routeID and (flight.progress=0 and route_path.sequence=1)
		where airplane_status = 'on_ground'
		) as info2 on info2.legID=leg.legID)
	) as d on d.support_tail=airplane.tail_num
group by arrival;

-- [16] people_in_the_air()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently airborne are located. */
-- -----------------------------------------------------------------------------
create or replace view people_in_the_air (departing_from, arriving_at, num_airplanes,
	airplane_list, flight_list, earliest_arrival, latest_arrival, num_pilots,
	num_passengers, joint_pilots_passengers, person_list) as
select leg.departure as departing_from, leg.arrival as arriving_at, count(distinct airplane.locationID) as num_airplanes, airplane.locationID as airplane_list,
	flightID as flight_list, next_time as earliest_arrival, next_time as latest_arrival, count(distinct pilot.personID) as num_pilots, count(distinct passenger_temp.personID) as num_passengers,
    (count(distinct pilot.personID) + count(distinct passenger_temp.personID)) as joint_pilots_passengers,
    group_concat(distinct person.personID order by person.personID) as person_list
from leg join route_path on leg.legID = route_path.legID 
	join flight on (flight.routeID = route_path.routeID and flight.progress = route_path.sequence)
    join airplane on airplane.tail_num = flight.support_tail
    join pilot on flight.flightID = pilot.commanding_flight
    join (select * from person where personID in (select personID from passenger)) as passenger_temp on airplane.locationID = passenger_temp.locationID
    join person on airplane.locationID = person.locationID
where airplane_status = 'in_flight'
group by flightID, airplane.locationID;

-- [17] people_on_the_ground()
-- -----------------------------------------------------------------------------
/* This view describes where people who are currently on the ground are located. */
-- -----------------------------------------------------------------------------
create or replace view people_on_the_ground (departing_from, airport, airport_name,
	city, state, country, num_pilots, num_passengers, joint_pilots_passengers, person_list) as
select airportID as departing_from, airport.locationID as airport, airport_name, city, state, country, count(distinct pilot_temp.personID) as num_pilots,
	count(distinct passenger_temp.personID) as num_passengers, (count(distinct pilot_temp.personID) + count(distinct passenger_temp.personID)) as joint_pilots_passengers,
    concat_ws(',', group_concat(distinct pilot_temp.personID), group_concat(distinct passenger_temp.personID)) as person_list
from airport left join (select * from person where personID in (select personID from pilot)) as pilot_temp on airport.locationID = pilot_temp.locationID 
	left join (select * from person where personID in (select personID from passenger)) as passenger_temp on airport.locationID = passenger_temp.locationID
    where (pilot_temp.personID is not null) or (passenger_temp.personID is not null)
group by airportID, airport_name, airport.locationID, city, state, country;

-- [18] route_summary()
-- -----------------------------------------------------------------------------
/* This view describes how the routes are being utilized by different flights. */
-- -----------------------------------------------------------------------------
create or replace view route_summary (route, num_legs, leg_sequence, route_length,
	num_flights, flight_list, airport_sequence) as
select route_path.routeID, count(distinct route_path.legID), group_concat(distinct route_path.legID order by route_path.sequence),
	cast((sum(distance) * count(distinct route_path.legID)/count(*)) as decimal(0,0)),
    count(distinct flightID), group_concat(distinct flightID),
	concat_ws(',', group_concat(distinct departure, '->', arrival order by route_path.sequence))
from route_path join leg on route_path.legID=leg.legID
	left join flight on (flight.routeID = route_path.routeID)
group by routeID;

-- [19] alternative_airports()
-- -----------------------------------------------------------------------------
/* This view displays airports that share the same city and state. */
-- -----------------------------------------------------------------------------
create or replace view alternative_airports (city, state, country, num_airports,
	airport_code_list, airport_name_list) as
select city, state, country, count(*) as num_airport, group_concat(airportID) as airport_code_list, group_concat(airport_name) as airport_name_list
from airport
group by city, state, country
having count(*) > 1;
