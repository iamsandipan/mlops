"""Define, upsert and start the SageMaker pipeline: preprocess -> train -> register.

Configuration comes from environment variables:
  SAGEMAKER_ROLE_ARN  execution role SageMaker assumes to run the jobs (required)
  SAGEMAKER_BUCKET    bucket for raw data and model artifacts (required)
  PIPELINE_NAME       defaults to mlops-pipeline
  INPUT_DATA          defaults to s3://<bucket>/raw/data.csv
"""
import argparse
import os
from pathlib import Path

import sagemaker
from sagemaker.estimator import Estimator
from sagemaker.inputs import TrainingInput
from sagemaker.model import Model
from sagemaker.processing import ProcessingInput, ProcessingOutput
from sagemaker.sklearn.processing import SKLearnProcessor
from sagemaker.workflow.model_step import ModelStep
from sagemaker.workflow.parameters import ParameterString
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.pipeline_context import PipelineSession
from sagemaker.workflow.steps import ProcessingStep, TrainingStep

HERE = Path(__file__).resolve().parent
INSTANCE_TYPE = "ml.m5.large"


def build_pipeline(role: str, bucket: str, name: str) -> Pipeline:
    session = PipelineSession()
    region = session.boto_region_name
    input_data = ParameterString(
        "InputData", default_value=os.environ.get("INPUT_DATA", f"s3://{bucket}/raw/data.csv")
    )

    processor = SKLearnProcessor(
        framework_version="1.2-1",
        role=role,
        instance_type=INSTANCE_TYPE,
        instance_count=1,
        sagemaker_session=session,
    )
    step_process = ProcessingStep(
        name="Preprocess",
        step_args=processor.run(
            code=str(HERE / "preprocess.py"),
            inputs=[ProcessingInput(source=input_data, destination="/opt/ml/processing/input")],
            outputs=[
                ProcessingOutput(output_name="train", source="/opt/ml/processing/train"),
                ProcessingOutput(output_name="validation", source="/opt/ml/processing/validation"),
            ],
        ),
    )

    image_uri = sagemaker.image_uris.retrieve("xgboost", region, version="1.7-1")
    estimator = Estimator(
        image_uri=image_uri,
        role=role,
        instance_type=INSTANCE_TYPE,
        instance_count=1,
        output_path=f"s3://{bucket}/models",
        sagemaker_session=session,
    )
    estimator.set_hyperparameters(objective="reg:squarederror", num_round=100)
    outputs = step_process.properties.ProcessingOutputConfig.Outputs
    step_train = TrainingStep(
        name="Train",
        step_args=estimator.fit({
            "train": TrainingInput(outputs["train"].S3Output.S3Uri, content_type="text/csv"),
            "validation": TrainingInput(outputs["validation"].S3Output.S3Uri, content_type="text/csv"),
        }),
    )

    model = Model(
        image_uri=image_uri,
        role=role,
        model_data=step_train.properties.ModelArtifacts.S3ModelArtifacts,
        sagemaker_session=session,
    )
    step_register = ModelStep(
        name="Register",
        step_args=model.register(
            content_types=["text/csv"],
            response_types=["text/csv"],
            inference_instances=[INSTANCE_TYPE],
            transform_instances=[INSTANCE_TYPE],
            model_package_group_name=f"{name}-models",
            approval_status="PendingManualApproval",
        ),
    )

    return Pipeline(
        name=name,
        parameters=[input_data],
        steps=[step_process, step_train, step_register],
        sagemaker_session=session,
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--no-start", action="store_true", help="only create or update the definition")
    parser.add_argument("--wait", action="store_true", help="wait for the execution to finish")
    args = parser.parse_args()

    role = os.environ["SAGEMAKER_ROLE_ARN"]
    bucket = os.environ["SAGEMAKER_BUCKET"]
    name = os.environ.get("PIPELINE_NAME", "mlops-pipeline")

    pipeline = build_pipeline(role, bucket, name)
    pipeline.upsert(role_arn=role)
    print(f"Upserted pipeline {name}")
    if args.no_start:
        return

    execution = pipeline.start()
    print(f"Started execution {execution.arn}")
    if args.wait:
        # Raises if the execution fails, so the CI job fails too. 30s x 120 = 1 hour max.
        execution.wait(delay=30, max_attempts=120)
        for step in execution.list_steps():
            print(f"{step['StepName']}: {step['StepStatus']}")


if __name__ == "__main__":
    main()
