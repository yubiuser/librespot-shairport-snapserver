##  MANUAL CONFLICT RESOLUTION REQUIRED

This Pull Request was automatically generated because the automated rebase of the branch `${{ github.ref_name }}` onto its upstream counterpart (`upstream/${{ github.ref_name }}`) failed due to merge conflicts.

Please follow these steps *locally* to resolve the conflicts and update the branch:

1.  **Ensure your local repository is up-to-date** (assuming you have added `upstream` remote):
    ```bash
    git fetch origin
    git fetch upstream
    ```
2.  **Checkout this branch:**
    ```bash
    git checkout ${{ github.ref_name }}
    ```
3.  **Attempt the rebase again locally:**
    ```bash
    git rebase upstream/${{ github.ref_name }}
    ```
    *(Note: The GitHub Action failed this step, you will likely encounter conflicts now.)*

4.  **Resolve each conflict:**
    -   Open the files listed by Git as having conflicts.
    -   Look for conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
    -   Edit the file to keep the code you want (combining your changes and upstream's changes as needed).
    -   **Remove** the conflict markers.
5.  **Stage the resolved files and continue the rebase:**
    ```bash
    git add <file1> <file2> ...  # Or git add .
    git rebase --continue
    ```
    Repeat steps 4 and 5 until the rebase completes without errors.

6.  **Force-push the rebased branch** to your fork:
    ```bash
    git push --force-with-lease origin ${{ github.ref_name }}
    ```
    *(This is safe because rebase rewrites history, and `--force-with-lease` prevents accidental overwrites if someone else pushed in the meantime).*

7.  **Merge or close this Pull Request on GitHub** once your local branch is successfully rebased and force-pushed. The PR serves mainly as a notification.