#!powershell

# (c) 2016, Cdiscount
#
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible. If not, see <http://www.gnu.org/licenses/>.


# WANT_JSON
# POWERSHELL_COMMON

function Compare-PropertyValue
{
    Param(
        [parameter(Mandatory=$true)]$Property,
        [parameter(Mandatory=$true)]$Value
    )

    if ($Property | Get-Member -Name "Value") {
        ($Property.Value -as [String]) -eq $Value
    } else {
        ($Property -as [String]) -eq $Value
    }
}

# Parameters
$params = Parse-Args $args

$path = Get-AnsibleParam -obj $params -name "path" -default "MACHINE/WEBROOT/APPHOST"
$filter = Get-AnsibleParam -obj $params -name "filter" -failifempty $true
$location = Get-AnsibleParam -obj $params -name "location"
$clr = Get-AnsibleParam -obj $params -name "clr"
$name = Get-AnsibleParam -obj $params -name "name"
$item = Get-AnsibleParam -obj $params -name "item"
$value = Get-AnsibleParam -obj $params -name "value"
$type = Get-AnsibleParam -obj $params -name "type" -ValidateSet "property","collection" -default "property"
$state = Get-AnsibleParam -obj $params -name "state" -ValidateSet "present","absent","locked","unlocked" -default "present"

if ($type -eq "property" -and $state -eq "absent") {
    Fail-Json "Invalid argument: state. The state 'absent' cannot be defined when type=property"
}

if ($clr -ne $null -and ($state -eq "locked" -or $state -eq "unlocked")) {
    Fail-Json "Invalid argument: clr. This argument cannot be defined when state=locked or unlocked"
}

if ($name -eq $null -and ($state -eq "present" -or $state -eq "absent" -or $type -eq "collection")) {
    Fail-Json "Missing required argument: name"
}

if ($item -eq $null -and $type -eq "collection" -and ($state -eq "present" -or $state -eq "absent")) {
    Fail-Json "Missing required argument: item"
} elseif ($item -ne $null -and $type -eq "property") {
    Fail-Json "Invalid argument: item. This argument cannot be defined when type=property"
}

if ($value -eq $null -and $type -eq "property" -and $state -eq "present") {
    Fail-Json "Missing required argument: value"
} elseif ($value -ne $null -and $name -eq $null) {
    Fail-Json "Invalid argument: value. This argument cannot be defined if name is not defined"
}

$attributes = @{}
if ($item -ne $null) {
    $itemKey, $itemValue = $item -split ":", 2, "SimpleMatch"
    if ($value -ne $null) {
        foreach ($attrStr in $value -split "|", 0, "SimpleMatch") {
            $k, $v = $attrStr -split ":", 2, "SimpleMatch"
            $attributes.Add($k, $v)
        }
    }
}

# Result
$result = New-Object psobject @{
    changed = $false
    data_changed = $false
    lock_status_changed = $false
}

# Ensure WebAdministration module is loaded
if ((Get-Module WebAdministration -ErrorAction SilentlyContinue) -eq $null) {
    Import-Module WebAdministration
}

# Set configuration element
if ($type -eq "property" -and $value -ne $null) {
    $arguments = @{
        PSPath = $path
        Filter = $filter
        Name = $name
    }
    if ($location -ne $null) {
        $arguments.Add("Location", $location)
    }
    if ($clr -ne $null) {
        $arguments.Add("Clr", $clr)
    }

    $property = Get-WebConfigurationProperty @arguments
    if ($property -eq $null) {
        Fail-Json $result "Unable to find configuration property"
    }

    if (-not (Compare-PropertyValue -Property $property -Value $value)) {
        try {
            $arguments.Add("Value", $value)
            Set-WebConfigurationProperty @arguments
            $result.changed = $true
            $result.data_changed = $true
        } catch {
            Fail-Json $result $_.Exception.Message
        }
    }
} elseif ($type -eq "collection" -and $item -ne $null) {
    $arguments = @{
        PSPath = $path
        Filter = $filter
        Name = $name
    }
    if ($location -ne $null) {
        $arguments.Add("Location", $location)
    }
    if ($clr -ne $null) {
        $arguments.Add("Clr", $clr)
    }

    $property = Get-WebConfigurationProperty @arguments
    if ($property -eq $null) {
        Fail-Json $result "Unable to find configuration collection"
    }
    if (-not ($property | Get-Member -Name "Collection")) {
        Fail-Json $result "Not a configuration collection"
    }

    $propertyItemList = @($property.Collection | Where-Object {$_.$itemKey -eq $itemValue})
    if ($propertyItemList -eq $null -or $propertyItemList.Count -eq 0) {
        $propertyItem = $null
    } elseif ($propertyItemList.Count -gt 1) {
        Fail-Json $result "Multiple property founds in the collection, the specified item option is not unique"
    } else {
        $propertyItem = $propertyItemList[0]
    }

    if ($state -eq "absent") {
        if ($propertyItem -ne $null) {
            # Remove item
            try {
                if ($name -ne ".") {
                    $arguments.Filter += "/$name"
                    $arguments.Name = "."
                }
                $arguments.Add("AtElement", @{$itemKey = $itemValue})

                Remove-WebConfigurationProperty @arguments
                $result.changed = $true
            } catch {
                Fail-Json $result $_.Exception.Message
            }
        }
    } else {
        if ($propertyItem -eq $null) {
            # Add new item
            try {
                if ($name -ne ".") {
                    $arguments.Filter += "/$name"
                    $arguments.Name = "."
                }
                $arguments.Add("Value", @{$itemKey = $itemValue} + $attributes)

                Add-WebConfigurationProperty @arguments
                $result.changed = $true
                $result.data_changed = $true
            } catch {
                Fail-Json $result $_.Exception.Message
            }
        } else {
            foreach ($key in $attributes.Keys) {
                if ($attributes.$key -ne $propertyItem.$key) {
                    # argument order is important for bool comparison
                    # Change item value
                    try {
                        if ($name -ne ".") {
                            $arguments.Filter += "/$name"
                        }
                        $arguments.Filter += "/" + $propertyItem.ElementTagName + "[@$itemKey='$itemValue']"
                        $arguments.Name = $key
                        $arguments.Add("Value", $attributes.$key)

                        Set-WebConfigurationProperty @arguments
                        $result.changed = $true
                        $result.data_changed = $true
                    } catch {
                        Fail-Json $result $_.Exception.Message
                    }
                }
            }
        }
    }
}

# Set locking status
if ($state -eq "locked" -or $state -eq "unlocked") {
    if ($type -eq "property") {
        if ($name -eq $null) {
            # Configuration section
            $arguments = @{
                PSPath = $path
                Filter = $filter
            }
            if ($location -ne $null) {
                $arguments.Add("Location", $location)
            }
            $sectionLock = Get-WebConfigurationLock @arguments

            if ($sectionLock -eq $null -and $state -eq "locked") {
                # Add lock
                try {
                    $arguments.Add("Type", "override")
                    Add-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            } elseif ($sectionLock -ne $null -and $state -eq "unlocked") {
                if ($sectionLock.Value -eq "Inherit") {
                    # The lock inherits from defaults, cannot remove it!
                    # So we must create a lock that override defaults, to
                    # remove then.
                    try {
                        $arguments.Add("Type", "override")
                        Add-WebConfigurationLock @arguments
                        $arguments.Remove("Type")
                    } catch {
                        Fail-Json $result $_.Exception.Message
                    }
                }

                # Remove lock
                try {
                    Remove-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            }
        } else {
            # Configuration property
            $arguments = @{
                PSPath = $path
                Filter = "$filter/@$name"
            }
            if ($location -ne $null) {
                $arguments.Add("Location", $location)
            }
            $propertyLock = Get-WebConfigurationLock @arguments

            if ($propertyLock -eq $null -and $state -eq "locked") {
                # Add lock
                try {
                    $arguments.Add("Type", "inclusive")
                    Add-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            } elseif ($propertyLock -ne $null -and $state -eq "unlocked") {
                # Remove lock
                try {
                    Remove-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            }
        }
    } else {
        # type=collection
        if ($item -eq $null) {
            # Configuration collection
            $arguments = @{
                PSPath = $path
                Filter = $filter
                Metadata = $null
            }
            if ($location -ne $null) {
                $arguments.Add("Location", $location)
            }
            $collection = Get-WebConfiguration @arguments
            if ($collection -eq $null) {
                Fail-Json $result "Unable to find configuration collection"
            }

            if ($collection.Metadata | Get-Member -Name "lockElements") {
                $lockElements = $collection.Metadata.lockElements -split ","
                if (-not $lockElements) {
                    $lockElements = [String[]]@()
                }
            } else {
                $lockElements = [String[]]@()
            }

            if ($name -notin $lockElements -and $state -eq "locked") {
                # Add lock
                try {
                    $arguments.Metadata = "lockElements"
                    $arguments.Add("Value", ($lockElements + $name) -join ",")
                    Set-WebConfiguration @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            } elseif ($name -in $lockElements -and $state -eq "unlocked") {
                # Remove lock
                try {
                    $arguments.Metadata = "lockElements"
                    $arguments.Add("Value", ($lockElements | Where-Object {$_ -ne $name}) -join ",")
                    Set-WebConfiguration @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            }
        } else {
            # Configuration item
            $arguments = @{
                PSPath = $path
                Filter = $filter
                Name = $name
            }
            if ($location -ne $null) {
                $arguments.Add("Location", $location)
            }
            if ($clr -ne $null) {
                $arguments.Add("Clr", $clr)
            }

            $property = Get-WebConfigurationProperty @arguments
            if ($property -eq $null) {
                Fail-Json $result "Unable to find configuration collection"
            }
            if (-not ($property | Get-Member -Name "Collection")) {
                Fail-Json $result "Not a configuration collection"
            }

            $propertyItemList = @($property.Collection | Where-Object {$_.$itemKey -eq $itemValue})
            if ($propertyItemList -eq $null -or $propertyItemList.Count -eq 0) {
                Fail-Json $result "Unable to find configuration item"
            } elseif ($propertyItemList.Count -gt 1) {
                Fail-Json $result "Multiple property founds in the collection, the specified item option is not unique"
            }

            $tag = $propertyItemList[0].ElementTagName

            $arguments = @{
                PSPath = $path
                Filter = "$filter/$name/$tag[@$itemKey='$itemValue']"
            }
            if ($location -ne $null) {
                $arguments.Add("Location", $location)
            }
            $itemLock = Get-WebConfigurationLock @arguments

            if ($itemLock -eq $null -and $state -eq "locked") {
                # Add lock
                try {
                    $arguments.Add("Type", "general")
                    Add-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            } elseif ($itemLock -ne $null -and $state -eq "unlocked") {
                # Remove lock
                try {
                    Remove-WebConfigurationLock @arguments
                    $result.changed = $true
                    $result.lock_status_changed = $true
                } catch {
                    Fail-Json $result $_.Exception.Message
                }
            }
        }
    }
}

Exit-Json $result