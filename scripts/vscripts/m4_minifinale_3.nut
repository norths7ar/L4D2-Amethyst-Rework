//m4_tower_minifinale2.nut
//Custom panic event while waiting for tower elevator. 0 tanks.

printl("Initiating m4_tower_minifinale3.nut");

//-----------------------------------------------------
local PANIC = 0
local TANK = 1
local DELAY = 2
//-----------------------------------------------------

DirectorOptions <-
{
	A_CustomFinale_StageCount = 4

	A_CustomFinale1 = PANIC
	A_CustomFinaleValue1 = 1
	
	A_CustomFinale2 = DELAY
	A_CustomFinaleValue2 = 5
	
	A_CustomFinale3 = PANIC
	A_CustomFinaleValue3 = 2
	
	A_CustomFinale4 = DELAY
	A_CustomFinaleValue4 = 1
}

function OnBeginCustomFinaleStage(num,type)
{
	if(num == 4)
	{
		EntFire("tower_minifinale_end_relay","trigger", "", 10);
	}
}