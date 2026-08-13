import { buildMesClient } from './_mesClient';
import { withReturnActions } from './_returnable';

export default withReturnActions(buildMesClient('production_records'));
