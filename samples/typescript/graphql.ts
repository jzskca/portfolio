import { ApolloError, useMutation } from "@apollo/client";

export type MutationHandler<Mutation extends ReturnType<typeof useMutation>[0]> = ({
    variables,
    onFinish,
    onError,
}: {
    variables: Parameters<Mutation>[0]["variables"];
    onFinish?: Parameters<ReturnType<Mutation>["then"]>[0];
    onError: (err: ApolloError) => void;
}) => ReturnType<Mutation>;

export type RelayMutationResponse = { clientMutationId: string };

/////////////////////////////////////////////////////////////////

export const useSampleMutation = () => {
    const [sampleMutation] = useMutation<SampleMutationResponse, SampleMutationVariables>(SAMPLE_MUTATION);
    const sample: MutationHandler<typeof sampleMutation> = ({ variables, onFinish, onError }) =>
        sampleMutation({ variables }).then(onFinish).catch(onError);
    return { sample };
};
