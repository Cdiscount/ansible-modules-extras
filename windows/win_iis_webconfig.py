#!/usr/bin/python
# -*- coding: utf-8 -*-

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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.


DOCUMENTATION = '''
---
module: win_iis_webconfig
version_added: "2.1"
short_description: Configures a IIS Web server.
description:
     - Sets, adds or removes IIS configuration elements.
options:
  path:
    description:
      - Configuration path, either an IIS configuration path in the format C(computer_name/webroot/apphost),
        or the IIS module path like C(IIS:\sites\Default Web Site).
    default: MACHINE/WEBROOT/APPHOST
  filter:
    description:
      - Configuration section or an XPath query that refers the configuration element.
    required: true
  location:
    description:
      - Location of the configuration setting.
    default: none
  clr:
    description:
      - Version of the .NET Framework in the form "vN.N", such as C(v2.0) or C(v4.0).
      - Cannot be specified when C(state=locked) or C(state=unlocked).
    default: none
  name:
    description:
      - Name of the configuration element.
      - Required if C(state=present) or C(state=absent), or if C(type=collection).
    default: none
  item:
    description:
      - If C(type=collection), specify the unique attribute of the collection item in the format "key:value".
      - Required if C(type=collection) and C(state=present) or C(absent), and cannot be specified if C(type=property).
    default: none
  value:
    description:
      - If C(type=property), value of the configuration property.
      - If C(type=collection), specify the attributes of the collection item referred by I(item),
        separated by a pipe and by a colon between each key and its value. E.g.: C(foo:1|bar:2).
      - Required if C(type=property) and C(state=present).
    default: none
  type:
    description:
      - Type of the configuration element to configure.
    choices:
      - property
      - collection
    default: property
  state:
    description:
      - State of the configuration element.
      - If C(state=locked) or C(state=unlocked), I(value) or I(item) can be specified to set the
        configuration element after locking or unlocking the property or the item.
    choices:
      - present
      - absent
      - locked
      - unlocked
    default: present
author: Jonathan Ravat
'''

EXAMPLES = '''
# Set a simple configuration property
- win_iis_webconfig: filter=system.webServer/defaultDocument name=enabled value=True

# Set a configuration property at a specific path for the .NET Framework v2.0
- win_iis_webconfig: path=MACHINE filter=system.web/deployment clr=v2.0 name=retail value=True

# Add a configuration item in a collection if does not exist
- win_iis_webconfig: filter=system.webServer/defaultDocument name=files item=value:main.html type=collection

# Add or set a configuration item in a collection
- win_iis_webconfig: filter=system.webServer/httpProtocol name=customHeaders item=name:X-Powered-By value=value:ASP.NET type=collection

# Remove a configuration item from a collection
- win_iis_webconfig: filter=system.webServer/defaultDocument name=files item=value:main.html type=collection state=absent

# Lock a configuration section
- win_iis_webconfig: filter=system.webServer/security/authentication/windowsAuthentication state=locked

# Unlock a configuration property
- win_iis_webconfig: filter=system.webServer/security/authentication/anonymousAuthentication name=enabled state=unlocked

# Lock a configuration property and set its value
- win_iis_webconfig: filter=system.webServer/security/authentication/windowsAuthentication name=enabled value=True state=locked

# Lock a configuration collection
- win_iis_webconfig: filter=system.webServer/defaultDocument name=files type=collection state=locked

# Add a configuration item if does not exist and lock it
- win_iis_webconfig: filter=system.webServer/defaultDocument name=files item=value:auth.html type=collection state=locked
'''
