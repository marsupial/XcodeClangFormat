#!/usr/bin/python
from __future__ import print_function
from urlparse import urlparse
import sys

URL  = urlparse(sys.argv[1])
URLPath = URL.path[:-4] if URL.path.endswith('.git') else URL.path
OriginURI = '%s%s' % ('.'.join(reversed(URL.netloc.split('.'))), URLPath.replace('/', '.'))
print('ORIGIN_URL = %s%s' % (URL.netloc, URLPath))
print('ORIGIN_URI = %s' % OriginURI)
print('ORIGIN_SHA = %s' % sys.argv[2])
print('PROJECT_IDENTIFIER = group.%s' % '.'.join(OriginURI.split('.')[1:]))
