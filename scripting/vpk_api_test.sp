/*
*	VPK_API - (Example Demo)
*	Copyright (C) 2021 Silvers
*
*	This program is free software: you can redistribute it and/or modify
*	it under the terms of the GNU General Public License as published by
*	the Free Software Foundation, either version 3 of the License, or
*	(at your option) any later version.
*
*	This program is distributed in the hope that it will be useful,
*	but WITHOUT ANY WARRANTY; without even the implied warranty of
*	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*	GNU General Public License for more details.
*
*	You should have received a copy of the GNU General Public License
*	along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/



#define PLUGIN_VERSION		"1.0"

/*======================================================================================
	Plugin Info:

*	Name	:	[ANY] VPK_API (Example Demo)
*	Author	:	SilverShot
*	Descrp	:	Read and Write files in VPK files.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=334905
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.1 (04-Dec-2021)
	- Changes to fix warnings when compiling on SourceMod 1.11.

1.0 (26-Oct-2021)
	- Initial release.

======================================================================================*/



#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <profiler>
#include <vpk_api>

float g_fAsynchronousExtracted;
float g_fAsynchronousPackaged;

int g_iVPK_Version;
EngineVersion g_iEngine;



// ====================================================================================================
//					PLUGIN INFO
// ====================================================================================================
public Plugin myinfo =
{
	name = "[ANY] VPK_API (Example Demo)",
	author = "SilverShot",
	description = "Read and Write files in VPK files.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=334905"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_iEngine = GetEngineVersion();
	switch( g_iEngine )
	{
		case Engine_AlienSwarm, Engine_DOTA, Engine_Left4Dead, Engine_Left4Dead2, Engine_Portal2:		g_iVPK_Version = 1;
		case Engine_CSGO, Engine_CSS, Engine_DODS, Engine_HL2DM, Engine_TF2:							g_iVPK_Version = 2;
		default:																						g_iVPK_Version = 1;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	RegAdminCmd("sm_vpk_api_test", CmdTest, ADMFLAG_ROOT, "Tests all features of the plugin.");

	// CmdTest(0, 0); // Execute on plugin load, for repeated recompiling and testing.
}



// ====================================================================================================
//					TEST
// ====================================================================================================
public Action CmdTest(int client, int args)
{
	PrintToServer("");
	PrintToServer("");
	PrintToServer("");
	PrintToServer("");
	PrintToServer("");



	// Debug testing and examples
	bool bTest_WriteSync		= true;
	bool bTest_WriteAsync		= true;
	bool bTest_ExtractSync		= true;
	bool bTest_ExtractAsync		= true;
	bool bTest_FileList			= true;
	bool bTest_Header			= true;



	// =========================
	// Vars
	// =========================
	char sDest[PLATFORM_MAX_PATH];
	char sPath[PLATFORM_MAX_PATH];
	char sTemp[PLATFORM_MAX_PATH];

	// Header
	char fileSize[16];
	char signature[16];
	int version;
	int TreeSize;

	ArrayList aList;
	ArrayList aSave;
	int files;
	int sizes;
	int size;

	bool result;



	// =========================
	// Benchmark
	// =========================
	Handle vProf = CreateProfiler();
	float fProf = 0.0;



	// =========================
	// Write Files - Synchronous
	// =========================
	if( bTest_WriteSync )
	{
		StartProfiling(vProf);

		sPath = "vpk_api_test/new_vpk_sync.vpk";
		aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

		// Files to write must exist or the VPK will not be created
		if( FileExists("gameinfo.txt") )								aList.PushString("gameinfo.txt");
		if( FileExists("mapcycle.txt") )								aList.PushString("mapcycle.txt");
		if( FileExists("motd.txt") )									aList.PushString("motd.txt");
		if( FileExists("maplist.txt") )									aList.PushString("maplist.txt");
		if( FileExists("scripts/gameserverconfig.vdf") )				aList.PushString("scripts/gameserverconfig.vdf");
		if( FileExists("scripts/kb_act.lst") )							aList.PushString("scripts/kb_act.lst");
		if( FileExists("cfg/pure_server_full.txt") )					aList.PushString("cfg/pure_server_full.txt");
		if( FileExists("cfg/pure_server_whitelist_example.txt") )		aList.PushString("cfg/pure_server_whitelist_example.txt");
		result = VPK_WriteFiles(sPath, aList, INVALID_FUNCTION);

		StopProfiling(vProf);
		fProf = GetProfilerTime(vProf);

		files = aList.Length;
		delete aList;

		size = FileSize(sPath);
		BytesToSize(size, fileSize, sizeof(fileSize));

		PrintToServer("-- VPK: Write Sync: create success: %s. Packaged (%d) files to \"%s\". %d bytes (%s). Took %f seconds to process.", result ? "true" : "false", files, sPath, size, fileSize, fProf);
		PrintToServer("");
		PrintToServer("");



		// =========================
		// Get file list
		// =========================
		StartProfiling(vProf);

		aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		files = VPK_GetFileList(sPath, aList);

		for( int i = 0; i < aList.Length; i ++ )
		{
			aList.GetString(i, sDest, sizeof(sDest));
			size = FileSize(sDest);
			BytesToSize(size, fileSize, sizeof(fileSize));
			PrintToServer("Test File List: \"%s\". %d bytes (%s)", sDest, size, fileSize);
		}

		delete aList;

		StopProfiling(vProf);
		fProf = GetProfilerTime(vProf);

		PrintToServer("-- VPK: File List: (%d) files in \"%s\". Took %f seconds to process", files, sPath, fProf);
		PrintToServer("");
		PrintToServer("");
	}



	// =========================
	// Write Files - Asynchronous
	// =========================
	if( bTest_WriteAsync )
	{
		g_fAsynchronousPackaged = GetEngineTime();

		sPath = "vpk_api_test/new_vpk_async.vpk";
		aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

		// Files to write must exist or the VPK will not be created
		if( FileExists("gameinfo.txt") )								aList.PushString("gameinfo.txt");
		if( FileExists("mapcycle.txt") )								aList.PushString("mapcycle.txt");
		if( FileExists("motd.txt") )									aList.PushString("motd.txt");
		if( FileExists("maplist.txt") )									aList.PushString("maplist.txt");
		if( FileExists("scripts/gameserverconfig.vdf") )				aList.PushString("scripts/gameserverconfig.vdf");
		if( FileExists("scripts/kb_act.lst") )							aList.PushString("scripts/kb_act.lst");
		if( FileExists("cfg/pure_server_full.txt") )					aList.PushString("cfg/pure_server_full.txt");
		if( FileExists("cfg/pure_server_whitelist_example.txt") )		aList.PushString("cfg/pure_server_whitelist_example.txt");

		VPK_WriteFiles(sPath, aList, OnPackagedFiles_All, g_iVPK_Version); // Writes to VPK version 1 or 2, depending on what is detected
	}



	// =========================
	// Extract files - Sync - Some files
	// =========================
	if( bTest_ExtractSync )
	{
		StartProfiling(vProf);

		sPath = "pak01_dir.vpk";
		switch( g_iEngine )
		{
			case Engine_TF2:		sPath = "tf2_misc_dir.vpk";
			case Engine_HL2DM:		sPath = "hl1mp_pak_dir.vpk";
		}

		sDest = "vpk_api_test/sync";

		if( FileExists(sPath) )
		{
			aSave = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
			aSave.PushString("maplist.txt");
			aSave.PushString("scripts/game_sounds.txt");
			aSave.PushString("scripts/hudlayout.res");
			aSave.PushString("resource/modevents.res");

			VPK_ExtractFiles(sPath, sDest, aSave);

			StopProfiling(vProf);
			fProf = GetProfilerTime(vProf);
			files = 0;

			for( int i = 0; i < aSave.Length; i++ )
			{
				aSave.GetString(i, sTemp, sizeof(sTemp));
				Format(sTemp, sizeof(sTemp), "%s/%s", sDest, sTemp);

				sizes = FileSize(sTemp);
				if( sizes != -1 )
				{
					size += sizes;
					files++;
				}

				BytesToSize(FileSize(sTemp), fileSize, sizeof(fileSize));
				PrintToServer("Test Extracted Sync: List: \"%s\". %d bytes (%s)", sTemp, FileSize(sTemp), fileSize);
			}

			delete aSave;

			BytesToSize(size, fileSize, sizeof(fileSize));
			PrintToServer("-- VPK: Extracted Sync: (%d) files from \"%s\" to \"%s\". %d bytes (%s). Took %f seconds to process.", files, sPath, sDest, size, fileSize, fProf);
			PrintToServer("");
			PrintToServer("");
		} else {
			PrintToServer("-- VPK: Extract Sync: Error: Missing file \"%s\"", sPath);
		}
	}




	// =========================
	// Extract files - Sync - All files
	// =========================
	if( bTest_ExtractSync )
	{
		StartProfiling(vProf);

		sPath = "vpk_api_test/new_vpk_sync.vpk";
		sDest = "vpk_api_test/all";

		if( FileExists(sPath) )
		{
			files = 0;
			aList = null;
			VPK_ExtractFiles(sPath, sDest, aList);

			StopProfiling(vProf);
			fProf = GetProfilerTime(vProf);
			size = 0;

			for( int i = 0; i < aList.Length; i ++ )
			{
				aList.GetString(i, sTemp, sizeof(sTemp));

				Format(sTemp, sizeof(sTemp), "%s/%s", sDest, sTemp);
				sizes = FileSize(sTemp);
				if( sizes != -1 )
				{
					size += sizes;
					files++;
				}

				BytesToSize(sizes, fileSize, sizeof(fileSize));
				PrintToServer("Test Extracted Sync All: List: \"%s\". %d bytes (%s)", sTemp, sizes, fileSize);
			}

			BytesToSize(size, fileSize, sizeof(fileSize));
			PrintToServer("-- VPK: Extracted Sync All: (%d) files from \"%s\" to \"%s\". %d bytes (%s). Took %f seconds to process.", files, sPath, sDest, size, fileSize, fProf);

			delete aList;

			PrintToServer("");
			PrintToServer("");
		} else {
			PrintToServer("-- VPK: Extract Sync All: Error: Missing file \"%s\"", sPath);
		}
	}



	// =========================
	// Extract files - Asynchronous method
	// =========================
	if( bTest_ExtractAsync )
	{
		g_fAsynchronousExtracted = GetEngineTime();

		sPath = "pak01_dir.vpk";
		switch( g_iEngine )
		{
			case Engine_TF2:		sPath = "tf2_misc_dir.vpk";
			case Engine_HL2DM:		sPath = "hl1mp_pak_dir.vpk";
		}

		sDest = "vpk_api_test/async";

		if( FileExists(sPath) )
		{
			aSave = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
			aSave.PushString("maplist.txt");
			aSave.PushString("scripts/game_sounds.txt");
			aSave.PushString("scripts/hudlayout.res");
			aSave.PushString("resource/modevents.res");
			files = aSave.Length;

			VPK_ExtractFiles(sPath, sDest, aSave, OnExtractedFiles_All);
		} else {
			PrintToServer("-- VPK: Extract Async Error: Missing file \"%s\"", sPath);
		}
	}



	// =========================
	// Get Header
	// =========================
	if( bTest_Header )
	{
		StartProfiling(vProf);

		sPath = "pak01_dir.vpk";
		switch( g_iEngine )
		{
			case Engine_TF2:		sPath = "tf2_misc_dir.vpk";
			case Engine_HL2DM:		sPath = "hl1mp_pak_dir.vpk";
		}

		if( FileExists(sPath) )
		{
			VPK_GetHeader(sPath, signature, version, TreeSize);
			BytesToSize(TreeSize, fileSize, sizeof(fileSize));
			size = FileSize(sPath);

			// Show header and Benchmark
			StopProfiling(vProf);
			fProf = GetProfilerTime(vProf);
			PrintToServer("-- VPK Header: File: \"%s\". Signature: %s. Version: %d. Header: %d [%d] bytes (%s). Took %f seconds to process.", sPath, signature, version, TreeSize, size, fileSize, fProf);
			PrintToServer("");
			PrintToServer("");
		} else {
			PrintToServer("-- VPK: Header Error: Missing file \"%s\"", sPath);
		}
	}



	// =========================
	// Get file list
	// =========================
	if( bTest_FileList )
	{
		StartProfiling(vProf);

		sPath = "pak01_dir.vpk";
		switch( g_iEngine )
		{
			case Engine_TF2:		sPath = "tf2_misc_dir.vpk";
			case Engine_HL2DM:		sPath = "hl1mp_pak_dir.vpk";
		}

		if( FileExists(sPath) )
		{
			aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
			files = VPK_GetFileList(sPath, aList);
			files = aList.Length;
			aList.GetString(GetRandomInt(0, aList.Length - 1), sDest, sizeof(sDest));
			PrintToServer("-- VPK: Showing random file: \"%s\"", sDest);

			// Show all files
			/*
			for( int i = 0; i < aList.Length; i++ )
			{
				aList.GetString(i, sDest, sizeof(sDest));
				PrintToServer("%4d %s", i, sDest);
			}
			// */

			delete aList;

			StopProfiling(vProf);
			fProf = GetProfilerTime(vProf);

			PrintToServer("-- VPK: \"%s\" has (%d) files. Took %f seconds to process.", sPath, files, fProf);
			PrintToServer("");
			PrintToServer("");
		} else {
			PrintToServer("-- VPK: Header Error: Missing file \"%s\"", sPath);
		}
	}

	return Plugin_Handled;
}

void OnExtractedFiles_All(const char sPath[PLATFORM_MAX_PATH], const char sDest[PLATFORM_MAX_PATH], ArrayList aSave)
{
	char fileSize[16];
	int files = aSave.Length;
	int size;

	// Display files extracted:
	if( aSave != null )
	{
		char sTemp[PLATFORM_MAX_PATH];
		files = aSave.Length;

		for( int i = 0; i < aSave.Length; i++ )
		{
			aSave.GetString(i, sTemp, sizeof(sTemp));
			Format(sTemp, sizeof(sTemp), "%s/%s", sDest, sTemp);

			size += FileSize(sTemp);
			BytesToSize(size, fileSize, sizeof(fileSize));

			PrintToServer("Test Extracted Async: \"%s\". %d bytes (%s)", sTemp, size, fileSize);
		}

		delete aSave;

		BytesToSize(size, fileSize, sizeof(fileSize));
	}

	size = FileSize(sPath);
	BytesToSize(size, fileSize, sizeof(fileSize));

	PrintToServer("-- VPK: Extracted Async: (%d) files from \"%s\" to \"%s\". %d bytes (%s). Took %f seconds to process", files, sPath, sDest, size, fileSize, GetEngineTime() - g_fAsynchronousExtracted);
	PrintToServer("");
	PrintToServer("");

	// Must delete the aSave handle
	delete aSave;
}

void OnPackagedFiles_All(const char sPath[PLATFORM_MAX_PATH], ArrayList aSave)
{
	char fileSize[16];
	int files = aSave.Length;
	int size;

	// Display files packaged:
	if( aSave != null )
	{
		char sTemp[PLATFORM_MAX_PATH];
		files = aSave.Length;

		for( int i = 0; i < aSave.Length; i++ )
		{
			aSave.GetString(i, sTemp, sizeof(sTemp));

			size += FileSize(sTemp);
			BytesToSize(size, fileSize, sizeof(fileSize));

			PrintToServer("Test Write Async: \"%s\". %d bytes (%s)", sTemp, size, fileSize);
		}

		delete aSave;

		BytesToSize(size, fileSize, sizeof(fileSize));
	}

	size = FileSize(sPath);
	BytesToSize(size, fileSize, sizeof(fileSize));

	PrintToServer("-- VPK: Write Async: Packaged (%d) files to \"%s\". %d bytes (%s). Took %f seconds to process", files, sPath, size, fileSize, GetEngineTime() - g_fAsynchronousPackaged);
	PrintToServer("");
	PrintToServer("");

	// Must delete the aSave handle
	delete aSave;
}