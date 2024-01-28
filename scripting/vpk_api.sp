/*
*	VPK_API
*	Copyright (C) 2024 Silvers
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



#define PLUGIN_VERSION		"1.2"

/*======================================================================================
	Plugin Info:

*	Name	:	[ANY] VPK_API (Reader and Writer)
*	Author	:	SilverShot
*	Descrp	:	Read and Write files in VPK files.
*	Link	:	https://forums.alliedmods.net/showthread.php?t=334905
*	Plugins	:	https://sourcemod.net/plugins.php?exact=exact&sortby=title&search=1&author=Silvers

========================================================================================
	Change Log:

1.2 (28-Jan-2024)
	- Fixed memory leak caused by clearing StringMap/ArrayList data instead of deleting.

1.1 (04-Dec-2021)
	- Changes to fix warnings when compiling on SourceMod 1.11.
	- Converted some code to use MethodMaps.

1.0 (26-Oct-2021)
	- Initial release.

======================================================================================*/



#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <profiler>
#include <vpk_api>


#define		MAX_PROCESS		0.3			// Maximum processing time (extraction and packing)

PrivateForward g_hForwardExtracted;
PrivateForward g_hForwardPackaged;



// ====================================================================================================
//					PLUGIN INFO
// ====================================================================================================
public Plugin myinfo =
{
	name = "[ANY] VPK_API (Reader and Writer)",
	author = "SilverShot",
	description = "Read and Write files in VPK files.",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=334905"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("VPK_GetHeader",			Native_VPK_GetHeader);
	CreateNative("VPK_GetFileList",			Native_VPK_GetFileList);
	CreateNative("VPK_ExtractFiles",		Native_VPK_ExtractFiles);
	CreateNative("VPK_WriteFiles",			Native_VPK_WriteFiles);

	g_hForwardExtracted = new PrivateForward(ET_Event, Param_String, Param_String, Param_Cell); 
	g_hForwardPackaged = new PrivateForward(ET_Event, Param_String, Param_Cell); 

	RegPluginLibrary("vpk_api");

	return APLRes_Success;
}



// ====================================================================================================
//					PLUGIN START
// ====================================================================================================
public void OnPluginStart()
{
	CreateConVar("vpk_api_version",	PLUGIN_VERSION, "VPK_API plugin version.");

	// ServerCommand("sm_vpk_api_test"); // Execute on plugin load, for repeated recompiling and testing.
}



// ====================================================================================================
// NATIVES
// ====================================================================================================
int Native_VPK_GetHeader(Handle plugin, int numParams)
{
	// Load File
	char sPath[PLATFORM_MAX_PATH];
	GetNativeString(1, sPath, sizeof(sPath));

	if( !FileExists(sPath) )
		return false;

	File hVPK = OpenFile(sPath, "rb");
	if( hVPK == null )
		return false;

	// Read Header
	int sig;
	int ver;
	int len;

	ReadFileCell(hVPK, sig, 4);
	ReadFileCell(hVPK, ver, 4);
	ReadFileCell(hVPK, len, 4);

	/* Read Version 2 header, possibly for future version if reading/listing this data. Unlikely to ever write.
	if( ver == 2 )
	{
		int FileDataSectionSize;
		int ArchiveMD5SectionSize;
		int OtherMD5SectionSize;
		int SignatureSectionSize;

		ReadFileCell(hVPK, FileDataSectionSize, 4);
		ReadFileCell(hVPK, ArchiveMD5SectionSize, 4);
		ReadFileCell(hVPK, OtherMD5SectionSize, 4);
		ReadFileCell(hVPK, SignatureSectionSize, 4);

		PrintToServer("Version 2 header: FileDataSectionSize=%d ArchiveMD5SectionSize=%d OtherMD5SectionSize=%d SignatureSectionSize=%d", FileDataSectionSize, ArchiveMD5SectionSize, OtherMD5SectionSize, SignatureSectionSize);
	}
	// */

	char signature[16];
	FormatEx(signature, sizeof(signature), "%X", sig);

	// Return Header
	SetNativeString(2, signature, sizeof(signature));
	SetNativeCellRef(3, ver);
	SetNativeCellRef(4, len);

	delete hVPK;
	return true;
}

int Native_VPK_GetFileList(Handle plugin, int numParams)
{
	// Load File
	char sPath[PLATFORM_MAX_PATH];
	GetNativeString(1, sPath, sizeof(sPath));

	if( !FileExists(sPath) )
		return -1;

	File hVPK = OpenFile(sPath, "rb");
	if( hVPK == null )
		return -1;

	// Read Files
	ArrayList aList = GetNativeCell(2);
	int files = ReadVPK(sPath, aList);

	delete hVPK;
	return files;
}

int Native_VPK_ExtractFiles(Handle plugin, int numParams)
{
	// Open path
	char sPath[PLATFORM_MAX_PATH];
	GetNativeString(1, sPath, sizeof(sPath));

	if( !FileExists(sPath) )
		return false;

	// Write path
	char sDest[PLATFORM_MAX_PATH];
	GetNativeString(2, sDest, sizeof(sDest));

	// File list
	ArrayList aSave = GetNativeCellRef(3);
	ArrayList aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	// Add callback
	Function callback = GetNativeFunction(4);
	if( callback != INVALID_FUNCTION ) g_hForwardExtracted.AddFunction(plugin, callback);

	// Open VPK
	ReadVPK(sPath, aList, sDest, aSave, null, callback != INVALID_FUNCTION ? plugin : null); // "plugin" variable is only used to identify that the process is asynchronous. Was thinking of using for some other features, but currently no plans to add.

	if( aSave == null )
	{
		SetNativeCellRef(3, aList);
	}

	return true;
}

int Native_VPK_WriteFiles(Handle plugin, int numParams)
{
	// Write path
	char sPath[PLATFORM_MAX_PATH];
	GetNativeString(1, sPath, sizeof(sPath));

	if( !CreateDirs(sPath) )
		return false;

	// File list
	char sTemp[PLATFORM_MAX_PATH];
	ArrayList aSave = GetNativeCell(2);

	// Add callback
	Function callback = GetNativeFunction(3);
	if( callback != INVALID_FUNCTION ) g_hForwardPackaged.AddFunction(plugin, callback);

	// Get format to write
	int versionVPK = GetNativeCell(4);
	if( versionVPK != 1 && versionVPK != 2 ) versionVPK = 1;

	// Check files exist
	int length = aSave.Length;
	for( int i = 0; i < length; i++ )
	{
		aSave.GetString(i, sTemp, sizeof(sTemp));

		if( !FileExists(sTemp) )
			return false;
		else if( !CreateDirs(sPath) )
			return false;
	}

	// Write VPK
	return CheckFilesForWriting(sPath, aSave, callback != INVALID_FUNCTION ? plugin : null, versionVPK); // "plugin" variable is only used to identify that the process is asynchronous. Was thinking of using for some other features, but currently no plans to add.
}



// ====================================================================================================
// READ VPK - FILE LIST - EXTRACT
// ====================================================================================================
// Asynchronous loading
Action TimerDelayExtract(Handle timer, DataPack dFrame)
{
	dFrame.Reset();

	char sPath[PLATFORM_MAX_PATH];
	char sDest[PLATFORM_MAX_PATH];
	ArrayList aList = dFrame.ReadCell();
	ArrayList aSave = dFrame.ReadCell();
	DataPack dPack = dFrame.ReadCell();
	Handle plugin = dFrame.ReadCell();
	dFrame.ReadString(sPath, sizeof(sPath));
	dFrame.ReadString(sDest, sizeof(sDest));

	delete dFrame;

	// Call again
	ReadVPK(sPath, aList, sDest, aSave, dPack, plugin);

	return Plugin_Continue;
}

// =========================
// Read VPK: Header - File list - Directory tree size - Extract files
// =========================
int ReadVPK(const char sPath[PLATFORM_MAX_PATH], ArrayList aList = null, const char sDest[PLATFORM_MAX_PATH] = "", ArrayList aSave = null, DataPack dPack = null, Handle plugin = null, int &archives = -1)
{
	// PrintToServer("ReadVPK path[%s] dest[%s] aList[%x] aSave[%x] dPack[%x] plugin[%x]", sPath, sDest, aList, aSave, dPack, plugin);
	float fTime = GetEngineTime();

	char sTemp[PLATFORM_MAX_PATH];
	char sFile[PLATFORM_MAX_PATH];
	char sLastDir[PLATFORM_MAX_PATH];
	char sLastExt[PLATFORM_MAX_PATH];

	ArrayList aArchives = new ArrayList();

	File hVPK;
	File hRead;
	File hSave;

	static int entryIndex;
	bool newSeg;	// New dir/ext detected
	int treeSize;	// Size of tree data section
	int files;		// File Count
	// int folders;	// Folder Count (shows wrong value due to duplicated directories I guess) - would need to save all and add unique ones only
	int iByte;		// Null byte check
	int iIndex;		// Index position of read/writing
	int version;	// VPK Version

	// VPKDirectoryEntry data
	int crc;		// Hash
	int bytes;		// PreloadBytes
	int index;		// ArchiveIndex
	int entry;		// EntryOffset
	int iSize;		// EntryLength
	int blank;		// Terminator



	// =========================
	// RESUME PROCESSING
	// =========================
	if( dPack != null )
	{
		dPack.Reset();

		iIndex = dPack.ReadCell();
		iSize = dPack.ReadCell();
		bytes = dPack.ReadCell();
		treeSize = dPack.ReadCell();
		entryIndex = dPack.ReadCell();
		archives = dPack.ReadCell();
		index = dPack.ReadCell();
		files = dPack.ReadCell();
		// folders = dPack.ReadCell();
		hVPK = dPack.ReadCell();
		hRead = dPack.ReadCell();
		hSave = dPack.ReadCell();
		plugin = dPack.ReadCell();
		dPack.ReadString(sFile, sizeof(sFile));
		dPack.ReadString(sTemp, sizeof(sTemp));
		dPack.ReadString(sLastDir, sizeof(sLastDir));
		dPack.ReadString(sLastExt, sizeof(sLastExt));

		// PrintToServer("ReadVPK_Read: iIndex=%d. iSize=%d. bytes=%d. Tree=%d. Entry=%d. index=%d. Files=%d. hVPK=%d. hSave=%d. hRead=%d. plug=%d. sFile=[%s]. sTemp=[%s]. Dir=[%s]. Ext=[%s] (V:%d/R:%d/S:%d)",
		// iIndex, iSize, bytes, treeSize, entryIndex, index, files, hVPK, hRead, hSave, plugin, sFile, sTemp, sLastDir, sLastExt, hVPK.Position, hRead.Position, hSave.Position);
		// PrintToServer("");
	}



	// =========================
	// LOAD FILE
	// =========================
	if( dPack == null ) // Null to load, otherwise resume processing
	{
		hVPK = OpenFile(sPath, "rb");
		if( hVPK == null )
		{
			return -1; // Already created and loaded by the server.
		}



		// =========================
		// GET HEADER END FOR EXTRACTION
		// =========================
		if( entryIndex == 0 && sDest[0] )
		{
			entryIndex = -1; // Because the var is static, we use in the next call
			entryIndex = ReadVPK(sPath, _, _, _, _, plugin, archives);
		}



		// =========================
		// LOAD HEADER
		// =========================
		VPK_GetHeader(sPath, _, version, treeSize); // Skipping signature

		// Skip Header
		hVPK.Seek(version == 1 ? 12 : 28, SEEK_SET);



		// =========================
		// READ DIRECTORY TREE
		// =========================
		newSeg = true;
	}



	// Loop entries
	// while( hVPK.Position < treeSize ) // This method would fail for asynchronous extraction.. because the file position on resume is past expected.
	do
	{
		if( dPack == null )
		{
			if( newSeg )
			{
				// =========================
				// New extension
				// =========================
				if( iByte == 0 )
				{
					iByte = 1;
					hVPK.ReadString(sTemp, sizeof(sTemp));
					if( strcmp(sTemp, "") && strncmp(sTemp, " ", 1) )
					{
						if( sTemp[0] == ' ' )
							sLastExt = "";
						else
							FormatEx(sLastExt, sizeof(sLastExt), ".%s", sTemp);

						// PrintToServer("NEW_EXT:: [%s] [%s]", sTemp, sLastExt);
					}
				}

				// =========================
				// New directory
				// =========================
				hVPK.ReadString(sTemp, sizeof(sTemp));
				if( strcmp(sTemp, "") && strncmp(sTemp, " ", 1) )
				{
					// folders++;
					strcopy(sLastDir, sizeof(sLastDir), sTemp);
					if( sLastDir[0] == ' ' )
						sLastDir = "";
					else
						StrCat(sLastDir, sizeof(sLastDir), "/");

					// PrintToServer("NEW_DIR:: [%s] [%s]", sTemp, sLastDir);
				}
			}



			// =========================
			// VPKDirectoryEntry
			// =========================
			hVPK.ReadString(sFile, sizeof(sFile));
			if( sFile[0] == 0 )
			{
				// PrintToServer("Skip null file @ %d", hVPK.Position);

				hVPK.Seek(hVPK.Position - 1, SEEK_SET);

				// This section must match the one below to find new ext/dir
				ReadFileCell(hVPK, iByte, 1);
				if( iByte == 0 || iByte == 255 )
				{
					newSeg = true;

					ReadFileCell(hVPK, iByte, 1);
					if( iByte != 0 )
					{
						hVPK.Seek(hVPK.Position - 1, SEEK_SET);
					} else {
					}
				} else {
					hVPK.Seek(hVPK.Position - 1, SEEK_SET);
				}

				continue;
			}

			files++;

			// 18 bytes per file data section
			ReadFileCell(hVPK, crc, 4);
			ReadFileCell(hVPK, bytes, 2); // PreloadBytes
			ReadFileCell(hVPK, index, 2); // ArchiveIndex
			ReadFileCell(hVPK, entry, 4); // EntryOffset
			ReadFileCell(hVPK, iSize, 4); // EntryLength
			ReadFileCell(hVPK, blank, 2); // Terminator



			// Check archive index
			if( index > archives && aArchives.FindValue(index) == -1 )
			{
				// Mark as checked
				aArchives.Push(index);

				// Verify path exists
				strcopy(sTemp, sizeof(sTemp), sPath);
				ReplaceString(sTemp, sizeof(sTemp), "_dir.vpk", "");
				Format(sTemp, sizeof(sTemp), "%s_%03d.vpk", sTemp, index);

				if( FileExists(sTemp) )
				{
					archives = index;
				}
			}



			// Make filename and push to ArrayList
			Format(sTemp, sizeof(sTemp), "%s%s%s", sLastDir, sFile, sLastExt);
			// PrintToServer("FILE: %4d [%s]", files, sTemp);

			if( sDest[0] == 0 && aList != null )
			{
				aList.PushString(sTemp);
			}
		}



		// =========================
		// Extract file
		// =========================
		// Extract all or match filename
		if( sDest[0] && (aSave == null || aSave.FindString(sTemp) != -1) )
		{
			if( aList != null )
			{
				aList.PushString(sTemp);
			}

			if( dPack == null || hRead == null )
			{
				Format(sTemp, sizeof(sTemp), "%s/%s", sDest, sTemp);
				if( !CreateDirs(sTemp) )
				{
					delete hVPK;
					return -1;
				}
				hRead = OpenFile(sPath, "rb");
			}

			if( hRead )
			{
				if( dPack == null || hSave == null )
				{
					if( FileExists(sTemp) )
						DeleteFile(sTemp);

					hSave = OpenFile(sTemp, "wb+");
				}

				if( hSave )
				{
					if( dPack == null )
					{
						// Save PreloadBytes section
						if( bytes )
						{
							hRead.Seek(hVPK.Position, SEEK_SET);

							for( int i = 0; i < bytes; i += 1)
							{
								ReadFileCell(hRead, blank, 1);
								WriteFileCell(hSave, blank, 1);
							}
						}
					}

					// Extract from archive
					if( iSize )
					{
						if( dPack == null )
						{
							// Build multiple archive path if required
							if( index >= 0 && index <= archives )
							{
								delete hRead;

								strcopy(sTemp, sizeof(sTemp), sPath);
								ReplaceString(sTemp, sizeof(sTemp), "_dir.vpk", "");
								Format(sTemp, sizeof(sTemp), "%s_%03d.vpk", sTemp, index);

								// Open archive path
								hRead = OpenFile(sTemp, "rb");
							} else {
								entry += entryIndex; // Skip header
							}
						}

						if( hRead )
						{
							if( dPack == null )
							{
								// Jump to entry position for extraction
								hRead.Seek(entry, SEEK_SET);
							} else {
								delete dPack;
							}

							for( int i = iIndex; i < iSize; i += 1)
							{
								ReadFileCell(hRead, blank, 1);
								WriteFileCell(hSave, blank, 1);

								// /* Asynchronous processing
								if( plugin && GetEngineTime() - fTime >= MAX_PROCESS )
								{
									FlushFile(hSave);

									dPack = new DataPack();

									dPack.WriteCell(i + 1);
									dPack.WriteCell(iSize);
									dPack.WriteCell(bytes);
									dPack.WriteCell(treeSize);
									dPack.WriteCell(entryIndex);
									dPack.WriteCell(archives);
									dPack.WriteCell(index);
									dPack.WriteCell(files);
									// dPack.WriteCell(folders);
									dPack.WriteCell(hVPK);
									dPack.WriteCell(hRead);
									dPack.WriteCell(hSave);
									dPack.WriteCell(plugin);
									dPack.WriteString(sFile);
									dPack.WriteString(sTemp);
									dPack.WriteString(sLastDir);
									dPack.WriteString(sLastExt);

									DataPack dFrame = new DataPack();
									dFrame.WriteCell(aList);
									dFrame.WriteCell(aSave);
									dFrame.WriteCell(dPack);
									dFrame.WriteCell(plugin);
									dFrame.WriteString(sPath);
									dFrame.WriteString(sDest);

									// PrintToServer("ReadVPK_Save: iIndex=%d. iSize=%d. bytes=%d. Tree=%d. Entry=%d. index=%d. Files=%d. hVPK=%d. hSave=%d. hRead=%d. plug=%d. sFile=[%s]. sTemp=[%s]. Dir=[%s]. Ext=[%s] @%f (V:%d/R:%d/S:%d) [%c]",
									// i + 1, iSize, bytes, treeSize, entryIndex, index, files, hVPK, hRead, hSave, plugin, sFile, sTemp, sLastDir, sLastExt, GetEngineTime() - fTime, hVPK.Position, hRead.Position, hSave.Position, blank);
									// PrintToServer("");

									CreateTimer(0.1, TimerDelayExtract, dFrame);
									return 0;
								}
								// */
							}

							iIndex = 0;

							FlushFile(hSave);
						} else {
							// PrintToServer("Error hRead.");
							break;
						}
					} else {
						// PrintToServer("Error iSize.");
					}
				} else {
					// PrintToServer("Error hSave.");
					break;
				}

				delete dPack;
				delete hRead;
				delete hSave;
			} else {
				// PrintToServer("Error hRead entry.");
				break;
			}
		}



		// Skip PreloadBytes
		if( bytes )
		{
			hVPK.Seek(hVPK.Position + bytes, SEEK_SET);
		}



		// =========================
		// Check for null bytes (new dir/ext)
		// =========================
		newSeg = false;
 
		// This section must match the one above to find new ext/dir
		ReadFileCell(hVPK, iByte, 1);
		if( iByte == 0 || iByte == 255 )
		{
			newSeg = true;

			ReadFileCell(hVPK, iByte, 1);
			if( iByte != 0 )
			{
				hVPK.Seek(hVPK.Position - 1, SEEK_SET);
			} else {
			}
		} else {
			hVPK.Seek(hVPK.Position - 1, SEEK_SET);
		}
	}
	while( hVPK.Position < treeSize );



	// =========================
	// Return end of file list
	// =========================
	if( entryIndex == -1 )
	{
		int pos = hVPK.Position + 1;
		delete hVPK;
		return pos;
	}



	// =========================
	// Callback
	// =========================
	if( plugin != null )
	{
		Call_StartForward(g_hForwardExtracted);
		Call_PushString(sPath);
		Call_PushString(sDest);
		Call_PushCell(aList);
		Call_Finish();
	}



	// =========================
	// Delete
	// =========================
	entryIndex = 0;
	delete dPack;
	delete hVPK;

	return files;
}



// ====================================================================================================
//					PREP FILES FOR VPK
// ====================================================================================================
bool CheckFilesForWriting(const char sPath[PLATFORM_MAX_PATH], ArrayList aList, Handle plugin, int versionVPK)
{
	aList = aList.Clone();

	// =========================
	// Sort
	// VPKs file trees are ordered by extension type, each unique filetype only appears once, organize the list for this case.
	// =========================
	SortADTArray(aList, Sort_Ascending, Sort_String);

	// Sort by extension
	ArrayList aSortList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	char sTempBuff[PLATFORM_MAX_PATH];
	int iDir;
	int iExt;



	// Loop main list
	for( int i = 0; i < aList.Length; i++ )
	{
		aList.GetString(i, sTempBuff, sizeof(sTempBuff));

		// Move extension to front, add to sort list
		iDir = FindCharInString(sTempBuff, '/', true);
		iExt = FindCharInString(sTempBuff, '.', true);
		if( iDir != -1 ) sTempBuff[iDir] = '\x0';
		if( iExt != -1 ) sTempBuff[iExt] = '\x0';

		if( iDir != -1 && iExt != -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s.%s/%s", sTempBuff[iExt + 1], sTempBuff, sTempBuff[iDir + 1]);
		else if( iDir == -1 && iExt != -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s.%s", sTempBuff[iExt + 1], sTempBuff);
		else if( iDir != -1 && iExt == -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s/%s", sTempBuff, sTempBuff[iDir + 1]);
		aSortList.PushString(sTempBuff);
	}



	// Order by extension, then folder names.
	SortADTArray(aSortList, Sort_Ascending, Sort_String);



	// Move extensions back, add to main list
	// .Clear() is creating a memory leak
	// aList.Clear();
	delete aList;
	aList = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	for( int i = 0; i < aSortList.Length; i++ )
	{
		aSortList.GetString(i, sTempBuff, sizeof(sTempBuff));

		iDir = FindCharInString(sTempBuff, '/');
		iExt = FindCharInString(sTempBuff, '.');

		if( iExt != -1 )
			sTempBuff[iExt] = '\x0';
		if( iDir != -1 )
			sTempBuff[iDir] = '\x0';

		if( iDir != -1 && iExt != -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s/%s.%s", sTempBuff[iExt + 1], sTempBuff[iDir + 1],sTempBuff);
		else if( iDir == -1 && iExt != -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s.%s", sTempBuff[iExt + 1], sTempBuff);
		else if( iDir != -1 && iExt == -1 )
			Format(sTempBuff, sizeof(sTempBuff), "%s/%s", sTempBuff, sTempBuff[iDir + 1]);

		aList.PushString(sTempBuff);
	}



	// =========================
	// Pack
	// =========================
	bool success = WriteVPK(sPath, aList, null, plugin, versionVPK);



	// =========================
	// Clean up
	// =========================
	if( plugin == null ) delete aList;

	delete aSortList;

	return success;
}



// ====================================================================================================
// WRITE VPK
// ====================================================================================================
Action TimerDelayPacking(Handle timer, DataPack dFrame)
{
	dFrame.Reset();

	char sPath[PLATFORM_MAX_PATH];
	dFrame.ReadString(sPath, sizeof(sPath));
	ArrayList aList = dFrame.ReadCell();
	DataPack dPack = dFrame.ReadCell();
	Handle plugin = dFrame.ReadCell();
	int versionVPK = dFrame.ReadCell();

	delete dFrame;

	// Call again
	WriteVPK(sPath, aList, dPack, plugin, versionVPK);

	return Plugin_Continue;
}

// =========================
// Write VPK: Header - File list - Directory tree size - Version 1 and 2 - synchronous and asynchronous
// =========================
bool WriteVPK(const char sPath[PLATFORM_MAX_PATH], ArrayList aList, DataPack dPack = null, Handle plugin = null, int versionVPK)
{
	// =========================
	// Number files, length
	// =========================
	char sFilePath[PLATFORM_MAX_PATH];
	char sLastDir[PLATFORM_MAX_PATH];
	char sLastExt[PLATFORM_MAX_PATH];
	char sTempBuff[PLATFORM_MAX_PATH];

	float fTime = GetEngineTime();
	File hSave;

	int iTreeBytes;
	int iDir;
	int iExt;
	int iPush;
	int iSize;



	if( dPack == null )
	{
		// =========================
		// Open + Write header
		// =========================
		hSave = OpenFile(sPath, "wb+");

		if( hSave == null )
		{
			return false; // Already created and loaded by the server.
		}

		WriteFileCell(hSave, 0x55AA1234, 4);	// Signature
		WriteFileCell(hSave, versionVPK, 4);	// Version

		// Writing null for now, calculated and written later.
		WriteFileCell(hSave, 0x00, 4);			// The size, in bytes, of the directory tree

		// V2 - Not writing any data for this, maybe one day.. Untested if games load the VPK correctly without footer section or if ignoring this section causes any sv_pure issues if the file is listed to be checked.
		if( versionVPK == 2 )
		{
			WriteFileCell(hSave, 0, 4);	// FileDataSectionSize
			WriteFileCell(hSave, 0, 4);	// ArchiveMD5SectionSize
			WriteFileCell(hSave, 0, 4);	// OtherMD5SectionSize
			WriteFileCell(hSave, 0, 4);	// SignatureSectionSize
		}



		// =========================
		// Write tree
		// =========================
		int crc32;
		int iEntry;

		for( int i = 0; i < aList.Length; i++ )
		{
			aList.GetString(i, sFilePath, sizeof(sFilePath));
			strcopy(sTempBuff, sizeof(sTempBuff), sFilePath);

			iDir = FindCharInString(sFilePath, '/', true);
			iExt = FindCharInString(sFilePath, '.', true);
			iPush = 0;



			// New ext
			if( iExt == -1 || strcmp(sLastExt, sFilePath[iExt + 1]) )
			{
				iPush = 1;

				if( iExt == -1 )
					sLastExt[0] = 0;
				else
					strcopy(sLastExt, sizeof(sLastExt), sFilePath[iExt + 1]);
			}



			// New dir
			if( iDir != -1 )
				sTempBuff[iDir] = '\x0';

			if( iDir == -1 || strcmp(sLastDir, sTempBuff) )
			{
				iPush += 2;
				strcopy(sLastDir, sizeof(sLastDir), sTempBuff);
			}



			// =========================
			// Write Extension
			// =========================
			if( iPush & (1<<0) )
			{
				if( i > 0 )
				{
					WriteFileCell(hSave, 0x00, 2);
					iTreeBytes += 2;
				}

				if( iExt == -1 )
				{
					WriteFileCell(hSave, 0x20, 1); // Space for no ext
					iTreeBytes += 2;
				} else {
					sTempBuff[iExt] = 0x00;
					WriteFileString(hSave, sTempBuff[iExt + 1], false);
					iTreeBytes += strlen(sTempBuff[iExt + 1]) + 1;
				}
				WriteFileCell(hSave, 0x00, 1);
			}



			// =========================
			// Write Folders
			// =========================
			if( iPush )
			{
				if( i > 0 && iPush == 2 )
				{
					WriteFileCell(hSave, 0x00, 1);
					iTreeBytes += 1;
				}

				if( iDir == -1 )
				{
					WriteFileCell(hSave, 0x20, 1); // Space for root dir
					iTreeBytes += 2;
				} else {
					sTempBuff[iDir] = '\x0';
					WriteFileString(hSave, sTempBuff, false);
					iTreeBytes += strlen(sTempBuff) + 1;
				}
				WriteFileCell(hSave, 0x00, 1);
			}



			// =========================
			// Filenames
			// =========================
			if( iExt != -1 )
				sFilePath[iExt] = 0x00;
			WriteFileString(hSave, sFilePath[iDir + 1], false);
			WriteFileCell(hSave, 0x00, 1);
			iTreeBytes += strlen(sFilePath[iDir + 1]);



			// =========================
			// File data
			// =========================
			// A 32bit CRC of the file's data.
			aList.GetString(i, sFilePath, sizeof(sFilePath));
			crc32 = CRC32_File(sFilePath);
			WriteFileCell(hSave, crc32, 4);

			// PreloadBytes
			// The number of bytes contained in the index file.
			WriteFileCell(hSave, 0x00, 2);

			// ArchiveIndex
			// A zero based index of the archive this file's data is contained in.
			// If 0x7fff, the data follows the directory.
			WriteFileCell(hSave, 0x7FFF, 2);

			iSize = FileSize(sFilePath);

			// EntryOffset
			WriteFileCell(hSave, iSize ? iEntry : 0, 4);
			iEntry += iSize;

			// EntryLength
			WriteFileCell(hSave, iSize, 4);

			// Terminator
			WriteFileCell(hSave, 0xFFFF, 2);

			// Last file terminator? FIXME: TODO: Check required
			if( iPush != 0 && i == aList.Length )
			{
				WriteFileCell(hSave, 0x00, 2);
				iTreeBytes += 2;
			}

			// Data section bytes
			iTreeBytes += 19;
		}

		// 2 null bytes end of tree header
		WriteFileCell(hSave, 0x00, 2);
		iTreeBytes += 2;

		// Sometimes 3?
		WriteFileCell(hSave, 0x00, 1);
		iTreeBytes += 1;
	}



	int iIndex;
	int xIndex;
	int iByte;
	File hRead;



	// =========================
	// RESUME PROCESSING
	// =========================
	if( dPack != null )
	{
		dPack.Reset();

		iIndex = dPack.ReadCell();
		xIndex = dPack.ReadCell();
		iSize = dPack.ReadCell();
		iTreeBytes = dPack.ReadCell();
		hSave = dPack.ReadCell();
		hRead = dPack.ReadCell();

		// PrintToServer("WriteVPK_Read: i=%d. x=%d. size=%d. Tree=%d. hSave=%d. hRead=%d.", iIndex, xIndex, size, iTreeBytes, hSave, hRead);
		// PrintToServer("");
	}



	// =========================
	// Concatenate files
	// =========================
	for( int i = iIndex; i < aList.Length; i++ )
	{
		// Read file
		aList.GetString(i, sFilePath, sizeof(sFilePath));
		if( dPack == null )
		{
			hRead = OpenFile(sFilePath, "rb");
			iSize = FileSize(sFilePath);
		} else {
			delete dPack;
		}
		// iTreeBytes += iSize; // FIXME: TODO: This should be correct, but it appears not.. so we loop files for iTreeBytes or use header bytes

		for( int x = xIndex; x < iSize; x += 1)
		{
			ReadFileCell(hRead, iByte, 1);
			WriteFileCell(hSave, iByte, 1);

			// /* Asynchronous processing
			if( plugin && GetEngineTime() - fTime >= MAX_PROCESS )
			{
				FlushFile(hSave);

				dPack = new DataPack();

				dPack.WriteCell(i);
				dPack.WriteCell(x + 1);
				dPack.WriteCell(iSize);
				dPack.WriteCell(iTreeBytes);
				dPack.WriteCell(hSave);
				dPack.WriteCell(hRead);

				DataPack dFrame = new DataPack();
				dFrame.WriteString(sPath);
				dFrame.WriteCell(aList);
				dFrame.WriteCell(dPack);
				dFrame.WriteCell(plugin);
				dFrame.WriteCell(versionVPK);

				// PrintToServer("WriteVPK_Save: i=%d. x=%d. Size=%d. Tree=%d. hSave=%d. hRead=%d.", i, x + 1, iSize, iTreeBytes, hSave, hRead);
				// PrintToServer("");

				CreateTimer(0.1, TimerDelayPacking, dFrame);
				return true;
			}
			// */
		}

		xIndex = 0;

		// Close read
		delete hRead;
	}



	// Set tree bytes count in header
	hSave.Seek(8, SEEK_SET);
	WriteFileCell(hSave, iTreeBytes, 4);



	// =========================
	// Callback
	// =========================
	if( plugin != null )
	{
		Call_StartForward(g_hForwardPackaged);
		Call_PushString(sPath);
		Call_PushCell(aList);
		Call_Finish();
	}



	// =========================
	// Close
	// =========================
	delete hSave;

	return true;
}



// ====================================================================================================
// CREATE DIRECTORIES
// ====================================================================================================
// Given a filename, create all missing folders and sub-folders to the path
bool CreateDirs(const char[] sFile)
{
	char sPath[PLATFORM_MAX_PATH];
	char sPart[PLATFORM_MAX_PATH];
	char sDir[PLATFORM_MAX_PATH];
	strcopy(sPath, sizeof(sPath), sFile);

	int pos;
	while( (pos = SplitString(sPath, "/", sPart, sizeof(sPart))) != -1 )
	{
		strcopy(sPath, sizeof(sPath), sPath[pos]);
		StrCat(sDir, sizeof(sDir), "/");
		StrCat(sDir, sizeof(sDir), sPart);

		if( DirExists(sDir) == false )
		{
			if( CreateDirectory(sDir, 511) == false )
				return false;
		}
	}

	return true;
}
