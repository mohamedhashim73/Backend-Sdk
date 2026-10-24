/// Public provider-agnostic data contracts.
library;

export '../contracts/data_backend.dart'
    show
        BackendRecord,
        BackendFunctionBackend,
        DataBackend,
        DescriptorCountBackend,
        DescriptorDeleteBackend,
        DescriptorDataBackend,
        validateRpcFunctionName;
export '../contracts/data_query_spec.dart' show DataQuerySpec;
