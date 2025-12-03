from nxpython import *

#p.addMappingDirective(getModels('*ram_1r1w*'), 'RAM', 'DFF')

p.setOptions({'ManageAsynchronousReadPort' : 'Yes',
              'AllowUnconfiguredIOs'       : 'Yes'
})
