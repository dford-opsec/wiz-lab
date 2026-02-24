terraform {
  backend "gcs" {
    bucket  = "tf-wiz" # Put the name of the bucket you just created here
    prefix  = "terraform/state"         # This creates a folder path inside the bucket
  }
}
