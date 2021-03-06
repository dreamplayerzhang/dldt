# Copyright (C) 2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

cmake_minimum_required (VERSION 2.8)
include ("extract")
include ("download_and_check")

function (GetNameAndUrlToDownload name url archive_name_unified archive_name_win archive_name_lin archive_name_mac)
  if (archive_name_unified)
    set (${url} "${archive_name_unified}" PARENT_SCOPE)
    set (${name} ${archive_name_unified} PARENT_SCOPE)
  else()
    if (LINUX OR (APPLE AND NOT archive_name_mac))
      if (NOT archive_name_lin)
        return()
      endif()  
      set (PLATFORM_FOLDER linux)
      set (archive_name ${archive_name_lin})
    elseif(APPLE)
      if (NOT archive_name_mac)
        return()
      endif()  
      set (PLATFORM_FOLDER mac)
      set (archive_name ${archive_name_mac})
    else()
      #if no dependency for target platfrom skip it
      if (NOT archive_name_win)
        return()
      endif()
      set (PLATFORM_FOLDER windows)
      set (archive_name ${archive_name_win})
    endif()

    set (${name} ${archive_name} PARENT_SCOPE)
    set (${url}  "${archive_name}" PARENT_SCOPE)
  endif()
endfunction(GetNameAndUrlToDownload)

#download from paltform specific folder from share server
function (DownloadAndExtractPlatformSpecific 
  component 
  archive_name_unified 
  archive_name_win 
  archive_name_lin 
  archive_name_mac 
  unpacked_path 
  result_path
  folder)

  GetNameAndUrlToDownload(archive_name RELATIVE_URL ${archive_name_unified} ${archive_name_win} ${archive_name_lin} ${archive_name_mac} )
  if (NOT archive_name OR NOT RELATIVE_URL)
    return()
  endif()
  CheckOrDownloadAndExtract(${component} ${RELATIVE_URL} ${archive_name} ${unpacked_path} result_path2 ${folder} TRUE FALSE TRUE)
  set (${result_path} ${result_path2} PARENT_SCOPE)

endfunction(DownloadAndExtractPlatformSpecific)

#download from common folder
function (DownloadAndExtract component archive_name unpacked_path result_path folder)
  set (RELATIVE_URL  "${archive_name}")
  set(fattal TRUE)
  CheckOrDownloadAndExtract(${component} ${RELATIVE_URL} ${archive_name} ${unpacked_path} result_path2 ${folder} ${fattal} result TRUE)
  
  if (NOT ${result})
    DownloadAndExtractPlatformSpecific(${component} ${archive_name} ${archive_name} ${archive_name} ${unpacked_path} ${result_path2} ${folder})
  endif()  

  set (${result_path} ${result_path2} PARENT_SCOPE)

endfunction(DownloadAndExtract)


function (DownloadAndExtractInternal URL archive_path  unpacked_path folder fattal result123)
  set (status "ON")
  DownloadAndCheck(${URL} ${archive_path} ${fattal} result1)
  if ("${result1}" STREQUAL "ARCHIVE_DOWNLOAD_FAIL")
    #check alternative url as well
    set (status "OFF")
    file(REMOVE_RECURSE "${archive_path}")    
  endif()

  if ("${result1}" STREQUAL "CHECKSUM_DOWNLOAD_FAIL" OR "${result1}" STREQUAL "HASH_MISMATCH")
    set(status FALSE)
    file(REMOVE_RECURSE "${archive_path}")    
  endif()

  if("${status}" STREQUAL "ON")
    ExtractWithVersion(${URL} ${archive_path} ${unpacked_path} ${folder} result)
  endif()
  
  set (result123 ${status} PARENT_SCOPE)

endfunction(DownloadAndExtractInternal)

function (ExtractWithVersion URL archive_path unpacked_path folder result)

  debug_message("ExtractWithVersion : ${archive_path} : ${unpacked_path}")
  extract(${archive_path} ${unpacked_path} ${folder} status)
  #dont need archive actually after unpacking
  file(REMOVE_RECURSE "${archive_path}")  
  if (${status})
    set (version_file ${unpacked_path}/ie_dependency.info)
    file(WRITE ${version_file} ${URL})
  else()
    file(REMOVE_RECURSE "${unpacked_path}")
  endif()
  set (${result} ${status} PARENT_SCOPE)  
endfunction (ExtractWithVersion)

function (DownloadOrExtractInternal URL archive_path unpacked_path folder fattal result123)
  debug_message("checking wether archive downloaded : ${archive_path}")

  if (NOT EXISTS ${archive_path})
    DownloadAndExtractInternal(${URL} ${archive_path} ${unpacked_path} ${folder} ${fattal} result)
  else()

    if (ENABLE_UNSAFE_LOCATIONS)
      ExtractWithVersion(${URL} ${archive_path} ${unpacked_path} ${folder} result)
      if(NOT ${result})
        DownloadAndExtractInternal(${URL} ${archive_path} ${unpacked_path} ${folder} ${fattal} result)      
      endif()
    else()
      debug_message("archive found on FS : ${archive_path}, however we cannot check it's checksum and think that it is invalid")
      file(REMOVE_RECURSE "${archive_path}")
      DownloadAndExtractInternal(${URL} ${archive_path} ${unpacked_path} ${folder} ${fattal} result)      
    endif()  

  
  endif()  

  if (NOT ${result})
    message(FATAL_ERROR "error: extract of '${archive_path}' failed")
  endif()

endfunction(DownloadOrExtractInternal)

file(REMOVE ${CMAKE_BINARY_DIR}/dependencies_64.txt)

function (CheckOrDownloadAndExtract component RELATIVE_URL archive_name unpacked_path result_path folder fattal result123 use_alternatives)
  set (archive_path ${TEMP}/download/${archive_name})
  set (status "ON")
  set (on_master FALSE)

  set (URL  "https://download.01.org/openvinotoolkit/2018_R3/dldt/inference_engine/${RELATIVE_URL}")

  #no message on recursive calls
  if (${use_alternatives})
    set(DEP_INFO "${component}=${URL}")
    debug_message (STATUS "DEPENDENCY_URL: ${DEP_INFO}")
    file(APPEND ${CMAKE_BINARY_DIR}/dependencies_64.txt "${DEP_INFO}\n")
  endif()

  debug_message ("checking that unpacked directory exist: ${unpacked_path}")

  if (NOT EXISTS ${unpacked_path})
    DownloadOrExtractInternal(${URL} ${archive_path} ${unpacked_path} ${folder} ${fattal} status)
  else(NOT EXISTS ${unpacked_path})  
    #path exists, so we would like to check what was unpacked version
    set (version_file ${unpacked_path}/ie_dependency.info)

    if (DEFINED TEAMCITY_GIT_BRANCH)
      if(${TEAMCITY_GIT_BRANCH} STREQUAL "master")
        set(on_master TRUE)
        debug_message ("On master branch, update data in DL_SDK_TEMP if necessary")
      endif()
    endif()

    if (NOT EXISTS ${version_file} AND NOT ${ENABLE_ALTERNATIVE_TEMP})
      clean_message(FATAL_ERROR "error: Dependency doesn't contain version file. Please select actions: \n"
        "if you are not sure about your FS dependency - remove it : \n"
        "\trm -rf ${unpacked_path}\n"
        "and rerun cmake.\n"
        "If your dependency is fine, then execute:\n\techo ${URL} > ${unpacked_path}/ie_dependency.info\n")
#     file(REMOVE_RECURSE "${unpacked_path}") 
#     DownloadOrExtractInternal(${URL} ${archive_path} ${unpacked_path} ${fattal} status)
    else()
      if (EXISTS ${version_file})
        file(READ "${version_file}" dependency_url)
        string(REGEX REPLACE "\n" ";" dependency_url "${dependency_url}")
        #we have decided to stick each dependency to unique url that will be that record in version file
        debug_message("dependency_info on FS : \"${dependency_url}\"\n"
                      "compare to            : \"${URL}\"" )
      else ()
        debug_message("no version file available at ${version_file}")
      endif()

    if (NOT EXISTS ${version_file} OR NOT ${dependency_url} STREQUAL ${URL})
      if (${use_alternatives} AND ALTERNATIVE_PATH AND NOT ${on_master})
        #creating alternative_path
        string(REPLACE ${TEMP} ${ALTERNATIVE_PATH} unpacked_path ${unpacked_path})
        string(REPLACE ${TEMP} ${ALTERNATIVE_PATH} archive_path ${archive_path})

        debug_message("dependency different: use local path for fetching updated version: ${alternative_path}")
        CheckOrDownloadAndExtract(${component} ${RELATIVE_URL} ${archive_name} ${unpacked_path} ${result_path} ${folder} ${fattal} ${result123} FALSE)

      else()
        debug_message("dependency updated: download it again")
        file(REMOVE_RECURSE "${unpacked_path}") 
        DownloadOrExtractInternal(${URL} ${archive_path} ${unpacked_path} ${folder} ${fattal} status)
      endif()
    endif ()
   endif()
  endif()

  if (${use_alternatives} OR ${on_master})
    set (${result123} "${status}" PARENT_SCOPE)
    set (${result_path} ${unpacked_path} PARENT_SCOPE)
  endif()

  
  
endfunction(CheckOrDownloadAndExtract)

