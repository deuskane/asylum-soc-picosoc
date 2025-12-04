from nxpython import *

#p.addMappingDirective(getModels('*ram_1r1w*'), 'RAM', 'DFF')

p.setOptions({'ManageAsynchronousReadPort' : 'Yes',
              'AllowUnconfiguredIOs'       : 'Yes' # It's workaround with bug in 25.1.0.6
})
